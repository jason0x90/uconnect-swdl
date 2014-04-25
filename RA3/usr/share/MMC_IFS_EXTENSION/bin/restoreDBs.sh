#!/bin/sh
source=$1
dest=$2

if [ ! -d  "$dest" ]; then
   mkdir -p "$dest"
fi

cp -R "$source"/* "$dest"

chmod +rwx "$dest"/*

exit
