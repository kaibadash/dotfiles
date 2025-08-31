[[ -f ~/.env ]] && source ~/.env
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="robbyrussell"
export ZSH_DISABLE_COMPFIX=true
plugins=(git)

# User configuration
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

source $ZSH/oh-my-zsh.sh
setopt nonomatch

export PATH="$HOME/.rbenv/bin:/opt/X11/bin:$PATH"
eval "$(rbenv init -)"

export PROMPT="%{$fg_bold[blue]%}${HOST} $PROMPT"
alias st="git status"
alias cm="git commit"
alias co="git checkout"
alias gtr="git log --graph --pretty='format:%C(yellow)%h%Creset %s %Cgreen(%an)%Creset %Cred%d%Creset'"
alias rpush="git push --set-upstream origin"
alias pull="git pull"
alias push="git push"
alias merge="git merge"
alias rs="bundle exec rspec --fail-fast"
alias bi="bundle install"
alias be="bundle exec"
alias rba="rubocop -A"
alias vg="vagrant"
mkcd() {
  \mkdir $* && cd $_
}
alias mkcd="mkcd"
replace() {
  if [ "$#" -lt 3 ]; then
    echo "Usage: replace from to dir1 [dir2 ... dirN]"
    return 1
  fi

  local from="$1"
  local to="$2"
  shift 2
  local dirs=("$@")

  for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
      find "$dir" -type f -exec gsed -i'' -e "s/$from/$to/g" {} \;
    else
      echo "Directory $dir does not exist"
    fi
  done
}
alias replace="replace"

export PATH=$HOME/.nodebrew/current/bin:$PATH

setopt nonomatch

export EDITOR=vim
eval "$(direnv hook zsh)"
eval "$(rbenv init -)"
eval $(docker-machine env default)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
export PATH="$HOME/.pyenv/shims:$PATH"
export PATH=$HOME/.nodebrew/current/bin:$PATH
export PATH="/usr/local/opt/libpq/bin:$PATH"
source /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc
source /opt/homebrew/share/google-cloud-sdk/path.zsh.inc
eval "$(/opt/homebrew/bin/brew shellenv)"

. /opt/homebrew/opt/asdf/libexec/asdf.sh
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/libxml2/bin:$PATH"

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

if [[ ! -n $TMUX ]]; then
  tmux new-session
fi

. `brew --prefix`/etc/profile.d/z.sh

export EMSDK_QUIET=1

# pnpm
export PNPM_HOME="${HOME}/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

