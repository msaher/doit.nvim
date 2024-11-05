local errors = require("compile.errors")

-- pattern to strip ansi escape sequences and carriage carriage-return
local strip_ansii_cr = "[\27\155\r][]?[()#;?%d]*[A-PRZcf-ntqry=><~]?"

---@param first_item string
---@param data string[]
---@param line_count number
---@return string
---@return number
local function pty_append_to_buf(buf, first_item, data, line_count)
    -- as per :h on_stdout, the first and last items may be partial when
    -- jobstart is passed the pty = true option.
    -- We set the first item as the first element and return the last item
    data[1] = first_item .. data[1]
    first_item = data[#data] -- next first item
    data[#data] = nil

    -- strip ansii sequences and remove \r character
    data = vim.tbl_map(function(line)
        return select(1, string.gsub(line, strip_ansii_cr, ""))
    end, data)

    vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, data)

        -- highlight captures
        for i, line in ipairs(data) do
            local cap = errors.match(line)
            if cap ~= nil then
                local idx = line_count + i - 1

                for k, span in pairs(cap) do
                    local byte_start = vim.str_byteindex(line, span.start - 1)
                    local byte_finish = vim.str_byteindex(line, span.finish - 1)
                    vim.api.nvim_buf_add_highlight(buf, -1, errors.highlights[k], idx, byte_start, byte_finish)
                end
            end
        end
    end)

    return first_item, #data
end

---@class Task
---@field bufname string?
---@field chan number?
---@field last_cmd string?
---@field last_cwd string?
local Task = {}
Task.__index = Task

---@return Task
function Task.new(bufname)
    local self = setmetatable({}, Task)
    self.bufname = bufname
    return self
end

--- creates a buffer ready for receiving pty job stdout.
--- the buffer's name is self.buffname
---@return number
function Task:_create_buf()
    buf = vim.api.nvim_create_buf(true, true)

    -- set buffer options
    vim.api.nvim_set_option_value("expandtab", false, { buf = buf })
    vim.api.nvim_set_option_value("tabstop", 8, { buf = buf })

    vim.keymap.set("n", "<CR>", function()
        -- must get the current buf manually instead of reusing outer buf
        -- otherwise it breaks if the buffer was renamed and another job has
        -- started that also called _create_buf()
        local buf = vim.api.nvim_get_current_buf()
        errors.set_buf(buf)

        local win = vim.api.nvim_get_current_win()
        local row = vim.api.nvim_win_get_cursor(win)[1]                     -- 1-based
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, true)[1] -- 0-based

        local data = errors.match(line)
        if data ~= nil then
            errors.enter(data, row-1)
        end
    end,
        { buffer = buf }
    )

    vim.api.nvim_buf_set_name(buf, self.bufname)

    return buf
end

---@return number?
function Task:_get_buf()
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.fs.basename(vim.api.nvim_buf_get_name(b)) == self.bufname end)

    return buf
end

function Task:rerun()
    if self.last_cmd ~= nil then
        self:run(self.last_cmd, { cwd = self.last_cwd })
    end
end

function Task:run(cmd, opts)
    -- first buffer with name `self.bufname`
    local buf = self:_get_buf()

    if buf ~= nil then
        if self.chan ~= nil then
            local choice = vim.fn.confirm("A task process is running; kill it?", "&No\n&Yes")

            if choice == 2 then -- yes
                vim.fn.jobwait({ self.chan }, 1500)
                self.chan = nil
            else
                return
            end
        else
            -- clear buffer
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {})
        end
    else
        -- we dont care if there's already a running job
        self.chan = nil
        buf = self:_create_buf()
    end

    -- if a cwd is not passed, use the current window's cwd
    opts = opts or {}
    local cwd = opts.cwd or vim.fn.getcwd(vim.api.nvim_get_current_win())

    local win = vim.fn.bufwinid(buf)
    if win == -1 then
        -- TODO: make this an opt
        win = vim.api.nvim_open_win(buf, false, {
            split = "right",
            win = -1,
        })
        vim.api.nvim_set_option_value("number", false, { win = win })
    end

    -- change cwd of task window
    vim.api.nvim_win_call(win, function()
        vim.cmd("lcd " .. cwd)
    end)

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
        "Running in " .. cwd,
        "Task started at " .. os.date("%a %b%e %H:%M:%S"),
        "",
        cmd,
    })
    local line_count = 4
    local first_item = ""

    self.chan = vim.fn.jobstart(cmd, {
        pty = true,        -- run in a pty. Avoids lazy behvaiour and quirks
        env = {
            PAGER = "",    -- disable paging. This is not interactive
            TERM = "dumb", -- tells programs to avoid actual terminal behvaiour. avoids stuff like colors
        },
        cwd = cwd,
        stdout_buffered = false, -- we'll buffer stdout ourselves
        on_stdout = function(chan, data, name)
            _ = name
            _ = chan

            local added
            first_item, added = pty_append_to_buf(buf, first_item, data, line_count)
            line_count = line_count + added
        end,

        on_exit = function(chan, exit_code, event)
            _ = chan
            _ = event -- always "exit"

            local now = os.date("%a %b%e %H:%M:%S")
            local msg
            if exit_code == 0 then
                msg = "Task finished at " .. now
            else
                msg = "Task existed abnormally with code " .. exit_code .. " at " .. now
            end
            vim.api.nvim_buf_set_lines(buf, -1, -1, true, { "", msg })
            self.chan = nil
        end
    })

    vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(data)
            _ = data
            if self.chan ~= nil then
                vim.fn.jobstop(self.chan)
            end
            self.chan = nil
            buf = nil

            return true
        end,
    })

    -- save last_cmd
    self.last_cmd = cmd
    self.last_cwd = cwd

    -- set buf as error buffer
    errors.set_buf(buf)
    errors.set_cwd(cwd)
end

local function main()
    -- clean *Task* if it exists
    local buf = vim.iter(vim.api.nvim_list_bufs()):find(function(b)
        return vim.fs.basename(vim.api.nvim_buf_get_name(b)) == "*Task*"
    end)

    if buf ~= nil then
        vim.api.nvim_buf_delete(buf, { force = true })
    end

    local t = Task.new("*Task*")
    vim.api.nvim_buf_create_user_command(0, "T", function()
        t:run("ls")
    end, { force = true })

    local last_input = nil
    vim.keymap.set("n", "<leader>r", function()
        input = vim.fn.input({ prompt = "Command to run: ", default = last_input or ""})
        if input ~= nil and input ~= "" then
            t:run(input)
            last_input = input
        end
    end)
end

main()
