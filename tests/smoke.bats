load test_helper

setup() {
  setup_yazi finder
  unset FZF_DEFAULT_OPTS FZF_DEFAULT_COMMAND FZF_CTRL_T_COMMAND FZF_CTRL_T_OPTS FZF_ALT_C_COMMAND FZF_ALT_C_OPTS FZF_CWD TMUX
  cat >"$YAZI_CONFIG_HOME/keymap.toml" <<'KEYS'
[mgr]
prepend_keymap = [
  { on = "z", run = "plugin finder file", desc = "Find a file" },
  { on = "Z", run = "plugin finder dir", desc = "Find a folder" },
  { on = "x", run = "plugin finder oops", desc = "A wrong argument" },
]
KEYS
  # fzf runs with --filter, which prints the match and exits: nothing is typed in the tests
  echo hello >"$WORK/aaa.txt"
  echo hello >"$WORK/needle.txt"
  mkdir -p "$WORK/aaa-dir" "$WORK/target-dir"
}

teardown() { stop_yazi; }

@test "the options of setup reach the picker of the files" {
  echo 'require("finder"):setup { file = { opts = "--filter=needle" } }' >"$YAZI_CONFIG_HOME/init.lua"
  start_yazi
  send_keys z
  assert_healthy
  assert_hovered "needle.txt"
}

@test "the picker of the folders finds a folder" {
  echo 'require("finder"):setup { dir = { opts = "--filter=target" } }' >"$YAZI_CONFIG_HOME/init.lua"
  start_yazi
  send_keys Z
  assert_healthy
  assert_hovered "target-dir"
}

@test "the variables of fzf for its key bindings are used with no setup at all" {
  export FZF_CTRL_T_OPTS="--filter=needle"
  start_yazi
  send_keys z
  assert_healthy
  assert_hovered "needle.txt"
}

@test "the command of fzf for its key bindings is used" {
  # the command prints one line, so --select-1 chooses it at once. With the files of the folder
  # there are two, and fzf would wait for a key
  export FZF_CTRL_T_COMMAND="printf 'needle.txt\n'"
  export FZF_CTRL_T_OPTS="--select-1"
  start_yazi
  send_keys z
  assert_healthy
  assert_hovered "needle.txt"
}

@test "a folder with a space and a semicolon in its name works" {
  local dir="$WORK/my dir; x"
  mkdir -p "$dir"
  echo hello >"$dir/aaa.txt"
  echo hello >"$dir/needle.txt"
  echo 'require("finder"):setup { file = { opts = "--filter=needle" } }' >"$YAZI_CONFIG_HOME/init.lua"
  start_yazi "$dir"
  send_keys z
  assert_healthy
  refute_screen "syntax error"
  assert_hovered "needle.txt"
}

@test "FZF_CWD that is empty or set does not break the picker" {
  export FZF_CWD="/somewhere"
  export FZF_CTRL_T_OPTS="--filter=needle --footer='files in /somewhere'"
  start_yazi
  send_keys z
  assert_healthy
  assert_hovered "needle.txt"
}

@test "a wrong argument is an error that says what to use" {
  start_yazi
  send_keys x
  assert_screen "plugin finder file"
}
