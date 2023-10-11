local async = require("neotest.async")
local lib = require("neotest.lib")
local Path = require("plenary.path")

local M = {}

function M.is_test_file(file_path)
  if not vim.endswith(file_path, ".py") then
    return false
  end
  local elems = vim.split(file_path, Path.path.sep)
  local file_name = elems[#elems]
  return vim.startswith(file_name, "test_") or vim.endswith(file_name, "_test.py")
end

M.module_exists = function(module, python_command)
  return lib.process.run(vim.tbl_flatten({
    python_command,
    "-c",
    "import imp; imp.find_module('" .. module .. "')",
  })) == 0
end


local python_command_mem = {}
local python_command_mem_container = {}
local available_container = {}

function M.available_container()
  if available_container["bool"] then
    return available_container["bool"]
  end

  if lib.files.exists(".devcontainer/devcontainer.json") then
    -- is the cli available? if so ensure the container is running
    local success, exit_code, _ = pcall(lib.process.run {
      "devcontainer", "up", "--workspace-folder", "." },
      { stdout = true })
    if success and exit_code == 0 then
      available_container["bool"] = true
      return available_container["bool"]
    end
  end
  -- fallback to false
  available_container["bool"] = true
  return available_container["bool"]
end

---@return string[]
function M.get_python_command(root)
  if python_command_mem_container[root] then
    return python_command_mem_container[root]
  end

  python_command_mem[root] = M.get_python_command_env(root)

  -- check if there is a runnable devcontainer
  if M.available_container(root) then
    python_command_mem_container[root] = vim.tbl_flatten({
      "devcontainer", "exec", "--workspace-folder",  ".",
      python_command_mem[root]
    })
    return python_command_mem_container[root]
  end

  -- fallback to regular get_python_command_env
  return python_command_mem[root]
end

---@return string[]
function M.get_python_command_env(root)
  if python_command_mem[root] then
    return python_command_mem[root]
  end
  -- Use activated virtualenv.
  if vim.env.VIRTUAL_ENV then
    python_command_mem[root] = { Path:new(vim.env.VIRTUAL_ENV, "bin", "python").filename }
    return python_command_mem[root]
  end

  for _, pattern in ipairs({ "*", ".*" }) do
    local match = async.fn.glob(Path:new(root or async.fn.getcwd(), pattern, "pyvenv.cfg").filename)
    if match ~= "" then
      python_command_mem[root] = { (Path:new(match):parent() / "bin" / "python").filename }
      return python_command_mem[root]
    end
  end

  if lib.files.exists("Pipfile") then
    local success, exit_code, data = pcall(lib.process.run, { "pipenv", "--py" }, { stdout = true })
    if success and exit_code == 0 then
      local venv = data.stdout:gsub("\n", "")
      if venv then
        python_command_mem[root] = { Path:new(venv).filename }
        return python_command_mem[root]
      end
    end
  end

  if lib.files.exists("pyproject.toml") then
    local success, exit_code, data = pcall(
      lib.process.run,
      { "poetry", "run", "poetry", "env", "info", "-p" },
      { stdout = true }
    )
    if success and exit_code == 0 then
      local venv = data.stdout:gsub("\n", "")
      if venv then
        python_command_mem[root] = { Path:new(venv, "bin", "python").filename }
        return python_command_mem[root]
      end
    end
  end

  -- Fallback to system Python.
  python_command_mem[root] = {
    async.fn.exepath("python3") or async.fn.exepath("python") or "python",
  }
  return python_command_mem[root]
end

return M
