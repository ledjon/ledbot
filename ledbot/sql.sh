#!/bin/sh

db="$1"

if [ "$db" = "" ]; then
	db="chanlogs"
fi

exec sqlite "./dbms/$db"
