function fish_greeting
    isatty stdout; and type -q fastfetch; and type -q python3; or return
    set -g __mini_fetch (python3 ~/.config/fastfetch/mini-panel.py)
    test (count $__mini_fetch) -eq 8; or return
    functions -c fish_prompt __mini_original_prompt

    function fish_prompt
        set -l original_status $status
        if set -q __mini_fetch[8]
            set -l width 0
            for line in $__mini_fetch[1..4]
                set -l n (string length --visible -- "$line")
                test $n -le $width; or set width $n
            end
            for i in 1 2 3 4
                set -l line $__mini_fetch[$i]
                if test $COLUMNS -gt (math $width + 24)
                    printf '%s%*s%s\n' "$line" (math $width + 4 - (string length --visible -- "$line")) '' $__mini_fetch[(math $i + 4)]
                else
                    if test $COLUMNS -le $width
                        set -l plain (string replace -ra '\x1b\[[0-9;]*m' '' -- "$line")
                        set plain (string replace -r '^.*?(?=|||)' '' -- "$plain")
                        set line (string shorten --max (math "max(1,$COLUMNS-1)") -- "$plain")
                    end
                    printf '%s\e[0m\n' "$line"
                end
            end
        end
        __mini_restore_status $original_status
        __mini_original_prompt
    end

    function __mini_restore_status
        return $argv[1]
    end
    function __mini_resize --on-variable COLUMNS
        if set -q __mini_fetch[8]; and status is-interactive
            commandline -f repaint 2>/dev/null
        end
    end
    function __mini_done --on-event fish_preexec
        set -e __mini_fetch
        functions -e fish_prompt
        functions -c __mini_original_prompt fish_prompt
        functions -e __mini_done __mini_resize __mini_restore_status __mini_original_prompt
    end
end
