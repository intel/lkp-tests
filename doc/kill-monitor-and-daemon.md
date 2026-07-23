# How to Kill Monitors and Daemons

When a job is finished, lkp-tests needs to stop any monitors and daemons
that were started for it. There are three supported ways to do this,
depending on how the daemon script itself is implemented.

## a) Kill it when the task is finished

Most daemons can be killed this way, and it is the default behavior
provided by lkp-tests. The only requirement is that the daemon script
runs the daemon with `exec` so it replaces the script process in the
foreground.

```sh
exec log_cmd netserver -4 -D
```

See [programs/netserver/daemon](../programs/netserver/daemon) as an example.

## b) Wait for a signal before killing it

If the daemon can't be run with `exec`, or has to run in the background,
kill it explicitly once the test completes:

```sh
setup_wait
./run_daemon &
pid=$!
wait_post_test
kill -9 "$pid"
```

See [programs/sockperf-server/daemon](../programs/sockperf-server/daemon)
as an example.

## c) Kill it in a customized way

If the daemon is launched in a special way (for example via `systemctl`),
the approaches above may not apply. In that case, register a custom
shutdown command to run during `post-run`:

```sh
cat > "$TMP_RESULT_ROOT/post-run.$daemon" <<EOF
your_kill_command
EOF
```

See [programs/httpd/daemon](../programs/httpd/daemon) as an example.
