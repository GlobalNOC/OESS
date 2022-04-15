#!/bin/bash

# /bin/bash rerunner.sh "/bin/rerun-me.pl" "/watch-dir-1 /watch-dir-2 ..."

sigint_handler()
{
  kill $PID
  exit
}

trap sigint_handler SIGINT

sleep 60

while true; do
  $1 &
  PID=$!
  inotifywait -r -e create -e modify -e delete -e move $2
  kill $PID
done
