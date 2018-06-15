#!/usr/bin/env bash

function error(){
    echo "======================"
    echo "ERROR"
    echo "======================"
    echo "$1"
    echo "======================"
    echo "try: sh $0 configure"
    echo "======================"
    exit 1
}

function notice(){
    echo "======================"
    echo "NOTICE"
    echo "======================"
    echo "$1"
    echo "======================"
}

function help(){
 echo "
    Usage: $0 [COMMAND]

    Commands:
        up          - Create and start projects
        down        - Stop and remove project containers, networks, images, and volumes
        configure   - Configure docker environment
        check       - ensure that all needed requirements for building environment has been met
        help        - print this message
    "
}