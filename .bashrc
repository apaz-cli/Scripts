# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    #alias grep='grep --color=auto'
    #alias fgrep='fgrep --color=auto'
    #alias egrep='egrep --color=auto'
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

export PATH="/home/apaz/git/system/Scripts:$PATH:/home/apaz/.local/bin"


case "$TERM" in
xterm*|rxvt*|screen)
    GREENISH="\[\033[32m\]"
    BLUISH="\[\033[94m\]"
    CYANISH="\[\033[96m\]"
    RESET="\[\033[00m\]"
    ;;
*)
    ;;
esac

__git_color() {
  local gb="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)";
  if [ -n "$gb" ]; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      printf "\033[31m"
    else
      printf "\033[32m"
    fi
  else
    printf "\033[32m"
  fi
}

__git_print() {
  local gb="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)";
  if [ -n "$gb" ]; then
      printf "$gb"
  else
    local nrepos="$(find . -maxdepth 2 -name .git -type d | wc -l)"
    if [ $nrepos -eq '0' ]; then
      printf "-"
    else
      printf "$nrepos"
    fi
  fi
}

PS1="\
$GREENISH\u\
$BLUISH[\
\[\$(if test \$? -eq 0; then echo '\033[32m'; else echo '\033[31m'; fi)\]x\
$BLUISH][\
\[\$(__git_color)\]\
\$(__git_print)\
$BLUISH][\
$GREENISH\w\
$BLUISH]\$\
$RESET \
"
