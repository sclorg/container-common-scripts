Common build helpers for sclorg containers
==========================================

This repository is aimed to be added as git submodule into particular
containers' source repositories.  By default, the path to submodule should be
named 'common'.

Regression tests
----------------

Just run `make check`

Dependencies for testsuite:

- docker
- docker-squash (version 1.0.5)
- git
- go-md2man
- make
- source-to-image
