# nix-darwin system module for ksh26
# Generates /etc/kshrc with nix environment setup, analogous to /etc/bashrc.
{ config, lib, ... }:

{
  environment.etc."kshrc".text = ''
    # /etc/kshrc: DO NOT EDIT -- this file has been generated automatically.
    # System-wide ksh configuration, analogous to /etc/bashrc.

    # Only execute this file once per shell.
    if [ -n "$__ETC_KSHRC_SOURCED" ]; then return; fi
    __ETC_KSHRC_SOURCED=1

    if [ -z "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]; then
      . ${config.system.build.setEnvironment}
    fi

    # Return early if not running interactively, but after nix setup.
    [[ -o interactive ]] || return 0

    ${config.system.build.setAliases.text}

    # Read system-wide modifications.
    if [ -f /etc/ksh.local ]; then
      . /etc/ksh.local
    fi
  '';
}
