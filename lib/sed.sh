#!/bin/bash

sed_uncolorize()
{
	sed -e 's/\x1b\[[0-9;]*m//g'
}
