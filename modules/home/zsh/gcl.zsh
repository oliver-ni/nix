gcl() {
    setopt localoptions
    setopt unset
    local descriptor="${1:-}"
    local url
    local urlhost
    local urlpath
    local autourl_proto

    if [[ $descriptor =~ '^[a-zA-Z0-9_-]+@([a-zA-Z0-9.-]+):(.*)$' ]]; then
        # full ssh url: user@host.name:path/to/repo
        url=$descriptor
        urlhost=$match[1]
        urlpath=$match[2]
    elif [[ $descriptor =~ '^https?://([a-zA-Z0-9.-]+)/(.*)$' ]]; then
        # full http url: https://host.name/path/to/repo
        url=$descriptor
        urlhost=$match[1]
        urlpath=$match[2]
    elif [[ $descriptor =~ '^([a-zA-Z0-9.-]+):(.*)$' ]]; then
        # abbreviated form with colon (ssh): host.name:path/to/repo
        urlhost=$match[1]
        urlpath=$match[2]
        autourl_proto=ssh
    elif [[ $descriptor =~ '^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*/[a-zA-Z0-9_.-]+$' ]]; then
        # valid github username/reponame
        urlhost=github.com
        urlpath=$descriptor
        autourl_proto=ssh
    elif [[ $descriptor =~ '^([a-zA-Z0-9.-]+)/(.*)$' ]]; then
        # abbreviated form with slash (http): host.name/path/to/repo
        urlhost=$match[1]
        urlpath=$match[2]
        autourl_proto=http
    else
        echo unknown
        return 1
    fi

    case $urlhost in
        github|gh) urlhost=github.com;;
        gitlab|gl) urlhost=gitlab.com;;
    esac

    if [[ -z $url ]]; then
        # force protocol to ssh for certain hosts
        case $urlhost in
            github.com|\
            gitlab.com)
                autourl_proto=ssh
                ;;
        esac

        case $autourl_proto in
            ssh)
                url=git@$urlhost:$urlpath
                ;;
            http)
                url=https://$urlhost/$urlpath
                ;;
        esac
    fi

    urlpath=${urlpath%.git}
    if [[ -z $urlpath || $urlpath == /* || /$urlpath/ == *'/../'* || /$urlpath/ == *'/./'* ]]; then
        print -u2 -- "Invalid repository path: $urlpath"
        return 1
    fi

    case $urlhost in
        github.com|\
        gitlab.com)
            # force add .git to end of url
            url=${url%.git}.git
            ;;
    esac

    local destination="$HOME/Development/$urlhost/$urlpath"
    if [[ ! -d "$destination/.jj" && ! -e "$destination/.git" ]]; then
        if [[ -e "$destination" ]]; then
            print -u2 -- "Not a repository: $destination"
            return 1
        fi
        jj git clone --colocate "$url" "$destination" || return
    fi
    builtin cd -- "$destination"
}
