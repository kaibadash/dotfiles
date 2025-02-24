if [[ ! -n $TMUX ]]; then
  tmux new-session
fi

export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"
export ZSH_DISABLE_COMPFIX=true

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

# User configuration

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

setopt nonomatch

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
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
#eval "$(pyenv init -)

export PATH="/Users/kaiba/.phpenv/bin:$PATH"
eval "$(phpenv init -)"

setopt nonomatch

export EDITOR=vim
eval "$(direnv hook zsh)"
eval "$(rbenv init -)"
eval $(docker-machine env default)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
export PATH="$HOME/.pyenv/shims:$PATH"

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[[ -f /Users/kaiba/.nodebrew/node/v8.1.1/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /Users/kaiba/.nodebrew/node/v8.1.1/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[[ -f /Users/kaiba/.nodebrew/node/v8.1.1/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /Users/kaiba/.nodebrew/node/v8.1.1/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh

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

