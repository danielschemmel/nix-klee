# Usage as a Development Environment
```console
$ nix develop
$ cd $KLEE_SRC
$ # TODO: Make this actually useful ;)
```

# Usage as Nix Package
```console
$ nix shell
$ klee --help
```

# Docker Usage
```console
$ nix build .#docker
$ docker load result
$ docker run --rm -it kleenix
(docker) # klee --help
```

# `/include`
The `/include` folder was generated by copying in `/usr/include/{asm,asm-generic,linux}` from a manjaro system running linux 6.7.4 on 2024-03-02.