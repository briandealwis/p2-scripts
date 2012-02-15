#
# Copyright 2011 Brian de Alwis
# Licensed under the Eclipse Public License v1.0
# http://www.eclipse.org/org/documents/epl-v10.php
#
# Tools / library used by p2 scripts
# Defined variables:
#   progname	the basename of the invoked script
#   verbose	whether to be verbose ("true" or "false")

error() {
    echo "${progname}: error: $*" 1>&2
    exit 1
}

# Check if $1, a local directory, looks like a p2 repository
# Return 0 if a local repo, or 1 if not
isLocalP2Repo() {
    if [ ! -d "$1" ]; then
	return 1
    elif [ ! -f "$1/artifacts.xml" -a ! -f "$1/artifacts.jar" \
	    -a ! -f "$1/compositeArtifacts.jar" \
	    -a ! -f "$1/content.xml" -a ! -f "$1/content.jar" \
	    -a ! -f "$1/compositeContent.jar" \
	    -a `ls -1 "$1" | wc -l` -gt 0 ]; then
	return 1
    fi
    return 0
}

# Vet and rewrite repository location.
# P2 expects local repositories to be absolute path names
# Ensures that local repositories exist.
#
# $1 = repository specification
#      can be a URL (e.g., file:/usr/local) or a path
# returns the rewritten repository location
rewriteRepoLoc() {
    case "$1" in
      http://*|https://*|ftp://*|sftp://*)
	echo "$1"
	;;
      file:*)
	path=$(echo "$1" | cut -d: -f2-)
        isLocalP2Repo "$path" || error "$1: not a repository"
	echo "file:$(absolute "$path")"
	;;
      *)
        if [ ! -d "$1" ]; then
            error "$1: repository location does not exist"
        fi
        isLocalP2Repo "$1" || error "$1: not a repository"
	echo "file:$(absolute "$1")"
    esac
}

# Vet and rewrite a set of comma-separated repository locations.
# P2 expects local repositories to be absolute path names
# Ensures that local repositories exist.
#
# $1 = repository specification
#      can be a URL (e.g., file:/usr/local) or a path
# returns the rewritten repository location
rewriteRepoLocs() {
    local OIFS=$IFS result
    IFS=,
    for repo in $*; do
	local rewrite=$(rewriteRepoLoc "$repo") || return 1
	if [ -z "$result" ]; then
	    result=$rewrite
	else
	    result="$result,$rewrite"
	fi
    done
    IFS=$OIFS
    echo $result
}

# Check that a local repo exists at the provided location,
# or create the directory
# $1 the location
checkOrCreateLocalP2Repo() {
    case "$1" in
      http://*|https://*|ftp://*|sftp://*)
	error "$1: not a local repository"
        ;;
      file:*)
	path=$(echo "$1" | cut -d: -f2-)
	;;
      *)
	path=$1;;
    esac
    if [ ! -d "$path" ]; then
	mkdir -p "$path" || exit 1
    else
	isLocalP2Repo "$path" || error "$1: not a repository"
    fi
    echo "file:$(absolute "$path")"
}

extractBundleSymbolicName() {
    # be ignore any trailing directives (e.g., singleton)
    sed -n \
      -e 's/^Bundle-SymbolicName:[ 	]*\([-a-zA-Z._0-9]*\).*/\1/p' "$@"
}

extractBundleVersion() {
    sed -n 's/^Bundle-Version:[ 	]*//p' "$@"
}

# Reflow the lines of a MANIFEST.MF as provided on stdin
# FIXME: I'm sure this could be done in a single line in Perl
rejoin() {
    sed -e 's/@/@@/g' -e 's/|/@!/g' -- "$@" \
    | tr -d '\015' \
    | tr '\012' '|' \
    | sed 's/|[[:space:]][[:space:]]*//g' \
    | tr '|' '\012' \
    | sed -e 's/@!/|/g' -e 's/@@/@/g'
}

# Extract the symbolic bundle name from provided bundle
# $1 the bundle
osgiBundleName() {
    if [ -d "$1" ]; then
	rejoin < "$1/META-INF/MANIFEST.MF" \
	    | extractBundleSymbolicName
    else
	unzip -p "$1" META-INF/MANIFEST.MF \
	    | rejoin \
	    | extractBundleSymbolicName
    fi
}

# Extract the bundle version from provided bundle
# $1 the bundle
osgiBundleVersion() {
    if [ -d "$1" ]; then
	rejoin < "$1/META-INF/MANIFEST.MF" \
	    | rejoin \
	    | extractBundleVersion
    else
	unzip -p "$1" META-INF/MANIFEST.MF \
	    | rejoin \
	    | extractBundleVersion
    fi
}

runEclipse() {
    local eclVerbose=""
    if [ "$verbose" = true ]; then
	eclVerbose="-debug /dev/null"
	echo "$ECLIPSEHOME/eclipse $eclVerbose -consolelog -nosplash $*"
    fi
    $ECLIPSEHOME/eclipse $eclVerbose -consolelog -nosplash "$@"
}

# helper function
getcwd() {
    /bin/pwd -P 2>/dev/null || /bin/pwd 2>/dev/null || pwd
}

# resolve the given file name
absolute() {
    if [ -z "$1" ]; then
	getcwd
	return
    elif [ -d "$1" ]; then
	(cd "$1"; getcwd)
	return
    fi

    dirname=$(dirname "$1")
    filename=$(basename "$1")
    # If symbolic link then recursively invoke ourselves on the linked file
    if [ -h "$1" ]; then
	# change to the directory of link so relative names are correct
	(cd "$dirname"; absolute $(readlink "$filename"))
    else
	while [ ! -d "$dirname" ]; do
	    filename=$(basename "$dirname")/"$filename"
	    dirname=$(dirname "$dirname")
	done
	if [ "$dirname" = / ]; then
	    echo "/$filename"
	else
	    (cd "$dirname"; echo "$(getcwd)/$filename")
	fi
    fi
}


progname=$(basename $0)

# allow verbose to be set from the environment
verbose=${verbose:-false}

if [ -z "$ECLIPSEHOME" ]; then
    error "ECLIPSEHOME must be set to Eclipse install with p2"
fi
