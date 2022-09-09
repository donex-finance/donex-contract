#!/bin/bash
pytest -n auto -s -W ignore::DeprecationWarning $1
