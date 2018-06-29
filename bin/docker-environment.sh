#!/usr/bin/env bash

# patterns
ALLNUM_PATTERN="[a-zA-Z0-9]+"
DIGIT_PATTERN="[0-9]+"

SELECTABLE_PROJECTS=(

)

SELECTABLE_PROJECTS_LIST=($(echo "${SELECTABLE_PROJECTS[@]} Done"))

DEFAULT_DEPENDENCIES="
    developer||allnum||Developer_S_name
    xdebug_host||ip||Xdebug_S_host(127.0.0.1)||127.0.0.1
    container.nginx.port||digit||Nginx_S_port(80)||80
    container.projects.name||allnum||Select_project_name
    container.projects.path||dir||Select_project_path
"

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


if test ! -d "$ROOT_PATH";then
    error "ROOT_PATH have to be defined"
fi

if test $? -gt 0;then
    # failed to determine root path
    exit 1
fi

function select_projects()
{
    select_projects=$1

    PS3="Please select projects:"

    selected_projects=()
    while :
    do
        clear
        echo "Selected projects: ${selected_projects[@]}"
        echo "--------------"
        options=("${SELECTABLE_PROJECTS_LIST[@]}")
        select project in "${options[@]}"
        do
            if [ "$project" == "Done" ];then
                break 2
            fi
            selected_projects+=" $project"
            selected_projects=($(echo "${selected_projects[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
            break
        done
    done
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

function configure()
{
    dependencies=("${DEFAULT_DEPENDENCIES[@]}")
    dependencies=$(printf "@@%s" "${DEFAULT_DEPENDENCIES[@]}")

    dependencies_data=''
    ask_dependencies "$dependencies"
    dump_config "$dependencies_data"
}

function explode()
{
    docker run --rm  php:alpine php -r '
        echo implode(" ", array_map("trim", explode($argv[1], $argv[2])));
    ' -- "$1" "$2"
}

function ask_dependencies()
{
    data=''
    rules=($(explode "@@" "$1"))

    for rule in "${rules[@]}"
    do
        :
        rule=($(explode "||" "$rule"))

        while :
            do
                echo "${rule[2]//_S_/ }:"
                read var

                if test ! -z "${rule[3]+x}" ;then
                    if test -z "$var" ;then
                        var="${rule[3]}"
                        break
                    fi
                fi

                case "${rule[1]}" in
                    allnum)
                        if [[ ! "$var" =~ $ALLNUM_PATTERN ]]; then
                            notice "Variable ${rule[0]} should comply with pattern $ALLNUM_PATTERN"
                            continue
                        fi
                        break
                        ;;
                    digit)
                        if [[ ! "$var" =~ $DIGIT_PATTERN ]]; then
                            notice "Variable ${rule[0]} should comply with pattern $DIGIT_PATTERN"
                            continue
                        fi
                        break
                        ;;
                    ip)
                        if [[ ! "$var" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                            notice "${rule[0]} should be a valid ip address"
                            continue
                        fi
                        break
                        ;;
                    dir)
                        if ! test -d "$var"; then
                            notice "Path $var not exists on your machine"
                            continue
                        fi
                        break
                        ;;
                    *)
                        notice "Unknown validator type ${rule[1]} for variable ${rule[0]}"
                        continue 2
                        ;;
                esac
            done
        dependencies_data="$dependencies_data&${rule[0]}=$var"
    done
}

function dump_config()
{
    op_result=$(
    docker run --rm --volume="$ROOT_PATH":/app php:alpine php -r '
        $fileName = "/app/vendor/kovalevgr/php-docker-environment/docker-environment.config.php";

        parse_str($argv[1], $vars);
        $varsFixed = [];
        foreach($vars as $varName => $var) {
            $keys = explode("_", $varName);
            $parent = &$varsFixed;
            while($key = array_shift($keys)) {
                if (empty($keys)) {
                    if (!is_array($parent)) {
                        throw new \UnexpectedValueException(sprintf(
                            "Option %s in colliding with already set value",
                            $varName
                        ));
                    }
                    $parent[$key] = $var;
                } else {
                    if (!isset($parent[$key])) {
                        $parent[$key] = [];
                    } elseif (!is_array($parent)) {
                        throw new \UnexpectedValueException(sprintf(
                            "Option %s in colliding with already set value",
                            $varName
                        ));
                    }
                    $parent = &$parent[$key];
                }
            }
        }

        $varsFixed['container']['projects'] = [$varsFixed['container']['projects']];

        if (file_exists($fileName)) {
            $config = require $fileName;

            $projects = $config['container']['projects'] ?? [];
            foreach ($projects as $project) {
                $varsFixed['container']['projects'][] = $project;
            }
        }

        file_put_contents($fileName, sprintf("<?php return %s;", var_export($varsFixed, true)));
    ' -- "$1")
    if test $? -gt 0; then
        error "$op_result"
    fi
}

function compile_docker_compose_config()
{
    op_result=$(
    docker run --rm --volume="$ROOT_PATH":/app php:alpine php -r '
        if (!file_exists("/app/vendor/kovalevgr/php-docker-environment/docker-environment.config.php")) {
            echo "Docker environment config have not been found";
            exit(1);
        }

        $config = require "/app/vendor/kovalevgr/php-docker-environment/docker-environment.config.php";

        require_once "/app/vendor/autoload.php";

        $twig = new Twig_Environment(new Twig_Loader_Filesystem(
            ["/app/vendor/kovalevgr/php-docker-environment/data"]
        ), ["debug" => true]);

        $twig->addExtension(new Twig_Extension_Debug());

        file_put_contents("/app/docker-compose.compiled.yml", $twig->render("docker-compose.tpl.yml.twig", $config));
        @mkdir("/app/vendor/kovalevgr/php-docker-environment/runtime/docker/dev/nginx", 0777, true);
        file_put_contents("/app/vendor/kovalevgr/php-docker-environment/runtime/docker/dev/nginx/nginx.conf", $twig->render("nginx/nginx.conf.twig", $config));
        @mkdir("/app/vendor/kovalevgr/php-docker-environment/runtime/docker/dev/fpm", 0777, true);
        file_put_contents("/app/vendor/kovalevgr/php-docker-environment/runtime/docker/dev/fpm/php-fpm.conf", $twig->render("fpm/php-fpm.conf.twig", $config));

    ' -- "$1"
    )
    if test $? -gt 0; then
        error "$op_result"
    fi
}

function reset_config()
{
    op_result=$(
    docker run --rm --volume="$ROOT_PATH":/app php:alpine php -r '
        if (file_exists("/app/docker-compose.compiled.yml")) {
            unlink("/app/docker-compose.compiled.yml");
        }

        if (file_exists("/app/vendor/kovalevgr/php-docker-environment/docker-environment.config.php")) {
            unlink("/app/vendor/kovalevgr/php-docker-environment/docker-environment.config.php");
        }

        delFolder("/app/vendor/kovalevgr/php-docker-environment/runtime");

        function delFolder($dir)
        {
            $files = array_diff(scandir($dir), array(".",".."));
            foreach ($files as $file) {
            (is_dir("$dir/$file")) ? delFolder("$dir/$file") : unlink("$dir/$file");
            }
            return rmdir($dir);
        }

    ' -- "$1"
    )
    if test $? -gt 0; then
        error "$op_result"
    fi
}

function help()
{
    echo "
            Usage: $0 [COMMAND]

            Commands:
                up          - Create and start projects
                down        - Stop and remove project containers, networks, images, and volumes
                configure   - Configure docker environment
                check       - ensure that all needed requirements for building environment has been met
                reset       - reset config environment
                help        - print this message
    "
}

function load_docker_environment_config(){
    # ensuring docker environment file is readable
    if ! test -r "./docker-environment.yml"
    then
        error "docker-environment.yml is not readable"
    fi

    docker_environment_content=$(<docker-environment.config.php)

    echo "$docker_environment_content"
}

check_dependencies

case "$1" in
    configure)
        configure
        ;;
    up)
        shift
        compile_docker_compose_config
        docker-compose -f docker-compose.compiled.yml up "$@"
        ;;
    down)
        shift
        docker-compose -f docker-compose.compiled.yml down "$@"
        ;;
    reset)
        shift
        reset_config
        ;;
    check)
        check_dependencies
        ;;
    *)
       help
       ;;
esac
