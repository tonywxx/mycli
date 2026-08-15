#!/bin/bash

git rm -r --cached "$1"
git commit -m "remove $1"
git push