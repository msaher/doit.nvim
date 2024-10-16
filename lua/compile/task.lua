---@class Task
---@field buf number?
---@field chan number?
local Task = {}
Task.__index = Task

---@return Task
function Task.new()
    local self = setmetatable({}, Task)
    return self
end

function Task:run(cmd, opts)
    -- TODO: make cmd a table if shell is false

    if self.buf ~= nil then
        if self.chan ~= nil then
            vim.ui.select({ "yes", "no" }, { prompt = "A task process is running; kill it?" }, function(choice, idx)
                _ = idx
                if choice == "yes" then
                    -- use jobwait() instead of jobstop() because it blocks
                    vim.fn.jobwait({ self.chan }, 1500)
                    self.chan = nil
                    self:run(cmd, opts)
                end
            end)
            return
        else
            -- clear buffer
            vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {})
        end
    else
        self.buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(self.buf, "*Task*")
    end

    opts = opts or {}
    local cwd = opts.cwd or vim.fn.getcwd(vim.api.nvim_get_current_win())

    local win = vim.fn.bufwinid(self.buf)
    if win == -1 then
        win = vim.api.nvim_open_win(self.buf, false, {
            split = "right"
        })
    end

    -- change cwd of task window
    vim.api.nvim_win_call(win, function()
        vim.cmd("lcd " .. cwd)
    end)

    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {
        "Running in " .. cwd,
        "Task started at " .. os.date("%a %b %e %H:%M:%S"),
        "",
        cmd,
    })

    self.chan = vim.fn.jobstart(cmd, {
        pty = true,     -- run in a pty. Avoids lazy behvaiour
        env = {
            PAGER = "", -- disable paging. This is not interactive
        },
        cwd = cwd,
        on_stdout = function(chan, data, name)
            _ = chan
            _ = name
            if not data then
                return
            end

            -- remove "\r" from non-empty strings
            -- remove empty strings and...
            -- Empty strings usually appear at the end {"foo\r", ""}
            local i = 1
            while i <= #data do
                if data[i]:sub(-1) == "\r" then
                    data[i] = data[i]:sub(1, -2)
                    i = i + 1
                elseif data[i] == "" then
                    table.remove(data, i)
                else
                    i = i + 1
                end
            end

            vim.schedule(function()
                vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, data)
            end)
        end,
        on_exit = function(chan, exit_code, event)
            _ = event -- always "exit"

            local now = os.date("%a %b %e %H:%M:%S")
            local msg
            if exit_code == 0 then
                msg = "Task finished at " .. now
            else
                msg = "Task existed abnormally with code " .. exit_code .. " at " .. now
            end
            vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, { "", msg })
            self.chan = nil
        end
    })

    vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = self.buf,
        callback = function(data)
            _ = data
            if self.chan ~= nil then
                vim.fn.jobstop(self.chan)
            end
            self.chan = nil
            self.buf = nil

            return true
        end,
    })
end
