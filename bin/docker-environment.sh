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

function check_dependencies()
{
    # ensure docker exists
    docker_version=$(docker -v)
    if ! test $? -eq 0;then
        error "docker is not available"
    fi

    # ensure docker-compose exists
    docker_compose_version=$(docker-compose -v)
    if ! test $? -eq 0;then
        error "docker-compose is not available"
    fi
}

if test ! -d "$ROOT_PATH";then
    error "ROOT_PATH have to be defined"
fi

if test $? -gt 0;then
    # failed to determine root path
    exit 1
fi

check_dependencies
