#!/bin/bash

git rm --cached "$1"
git commit -m "remove $1"
git push