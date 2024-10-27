local errors = require("compile.errors")
local busted = require("plenary.busted")


local function tbl_equal(a, b)
    if a == b then return true end

    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    for k, v in pairs(a) do
        if type(v) == "table" then
            if not tbl_equal(v, b[k]) then
                return false
            end
        else
            if v ~= b[k] then
                return false
            end
        end
    end

    -- make "a" has all keys "b" has
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end


busted.describe("error patterns", function()

    local cases = {
        { rule = "absoft", line = "Error on line 3 of t.f: Execution error unclassifiable statement", want = {row_start = 3, filename = "t.f" }},
        { rule = "absoft", line = "Line 45 of \"foo.c\": bloofle undefined", want = {row_start = 45, filename = "foo.c" }},
        { rule = "absoft", line = "error on line 19 of fplot.f: spelling error?", want = {row_start = 19, filename = "fplot.f" }},
        { rule = "absoft", line = "warning on line 17 of fplot.f: data type is undefined for variable d", want = {row_start = 17, filename = "fplot.f" }},

        { rule = "ada", line = "foo.adb:61:11:  [...] in call to size declared at foo.ads:11", want = {row_start = 11, filename = "foo.ads"}},
        { rule = "ada", line = "0x8008621 main+16 at error.c:17", want = { row_start = 17, filename = "error.c" }},

        { rule = "aix", line = "****** Error number 140 in line 8 of file errors.c ******", want = {row_start = 8, filename = "errors.c"}},

        { rule = "ant",  line = "[javac] /src/DataBaseTestCase.java:27: unreported exception ...", want = {row_start = 27, filename = "/src/DataBaseTestCase.java"}},
        { rule = "ant",  line = "[javac] /src/DataBaseTestCase.java:49: warning: finally clause cannot complete normally", want = {row_start = 49, filename = "/src/DataBaseTestCase.java", type = "warning"}},
        { rule = "ant",  line = "[jikes]  foo.java:3:5:7:9: blah blah", want = {col_start = 5, col_end = 9, row_start = 3, row_end = 7, filename = "foo.java"}},
        { rule = "ant",  line = "[javac] c:/cygwin/Test.java:12: error: foo: bar", want = {row_start = 12, filename = "c:/cygwin/Test.java"}},
        { rule = "ant",  line = "[javac] c:\\cygwin\\Test.java:87: error: foo: bar", want = {row_start = 87, filename = "c:\\cygwin\\Test.java"}},
        -- -- Checkstyle error, but ant reports a warning (note additional
        -- -- severity level after task name)
        {rule = "ant", line = "[checkstyle] [ERROR] /src/Test.java:38: warning: foo", want = {row_start = 38, filename = "/src/Test.java", type = "warning"}},

        {rule = "bash", line = "a.sh: line 1: ls-l: command not found", want = {row_start = 1, filename = "a.sh"}},

        { rule = "borland", line = "Error ping.c 15: Unable to open include file 'sys/types.h'", want = {row_start = 15, filename = "ping.c"}},
        { rule = "borland", line = "Warning pong.c 68: Call to function 'func' with no prototype",  want = {row_start = 68, filename = "pong.c", type = "warning"}},
        { rule = "borland", line = "Error E2010 ping.c 15: Unable to open include file 'sys/types.h'",  want = {row_start = 15, filename = "ping.c"}},
        { rule = "borland", line = "Warning W1022 pong.c 68: Call to function 'func' with no prototype",  want = {row_start = 68, filename = "pong.c", type = "warning"}},

        { rule = "python_tracebacks_and_caml", line = "File \"foobar.ml\", lines 5-8, characters 20-155: blah blah", want = {col_start = 20, col_end = 155, row_start = 5, row_end = 8, filename = "foobar.ml"}},
        { rule = "python_tracebacks_and_caml", line = "File \"F:\\ocaml\\sorting.ml\", line 65, characters 2-145:\nWarning 26: unused variable equ.", want = {col_start = 2, col_end = 145, row_start = 65, filename = "F:\\ocaml\\sorting.ml"}},
        { rule = "python_tracebacks_and_caml", line = "File \"/usr/share/gdesklets/display/TargetGauge.py\", line 41, in add_children", want = {row_start = 41, filename = "/usr/share/gdesklets/display/TargetGauge.py"}},
        { rule = "python_tracebacks_and_caml", line = "File \\lib\\python\\Products\\PythonScripts\\PythonScript.py, line 302, in _exec", want = {row_start = 302, filename = "\\lib\\python\\Products\\PythonScripts\\PythonScript.py"}},
        { rule = "python_tracebacks_and_caml", line = "File \"/tmp/foo.py\", line 10", want = {row_start = 10, filename = "/tmp/foo.py"}},
    }

    busted.it("captures error information", function()
        for i, v in ipairs(cases) do
            local got = errors.patterns[v.rule]:match(v.line)
            assert(
                tbl_equal(got, v.want),
                string.format("Test #%d failed for rule '%s' with line '%s'\n\tgot %s, want %s", i, v.rule, v.line, vim.inspect(got), vim.inspect(v.want))
            )
        end
    end)
end)

