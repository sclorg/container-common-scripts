#!/bin/bash

# This script is used to create image directories using distgen, cp or ln
# It requires manifest.sh file to be present in image repository
# The manifest file should contain set of rules in form:
# <rules_type>="
# src=<path to source>
# dest=<path to destination>
# mode=<destination file mode (optional)>;
# ...;
# "
#
# Supported type rules are now COPY_RULES, DISTGEN_RULES and SYMLINKS_RULES
# for real example see https://github.com/sclorg/postgresql-container/blob/master/manifest.sh

source manifest.sh

die () { echo "FATAL: $*" ; exit 1 ; }

nl='
'

test -f auto_targets.mk && rm auto_targets.mk

DISTGEN_COMBINATIONS=$(${DG-/bin/dg} --multispec specs/multispec.yml --multispec-combinations)

clean_rule_variables(){
    src=""
    dest=""
    mode=""
    link_target=""
    link_name=""
}

parse_rules() {
    targets=""
    OLD_IFS=$IFS
    IFS=";"
    for rule in $rules; do
        if [ -z $(echo "$rule"| tr -d '[:space:]') ]; then
            continue
        fi
        clean_rule_variables
        eval $rule

        cdir='$(CDIR)'
        case "$creator" in
            copy)
                [[ -z "$src" ]] && echo "src has to be specified in copy rule" && exit 1
                [[ -z "$dest" ]] && echo "dest has to be specified in copy rule" && exit 1
                core_subst=$core
                prolog="\$(V_CP)$cdir"
                ;;
            distgen)
                [[ -z "$src" ]] && echo "src has to be specified in distgen rule" && exit 1
                [[ -z "$dest" ]] && echo "dest has to be specified in distgen rule" && exit 1
                core_subst=$core
                prolog="\$(V_DG)$cdir"
                ;;
            distgen_multi)
                [[ -z "$src" ]] && echo "src has to be specified in distgen rule" && exit 1
                [[ -z "$dest" ]] && echo "dest has to be specified in distgen rule" && exit 1

                if [[ "$dest" == "Dockerfile.rhel7" ]]; then
                    if ! [[ "$DG_CONF" =~ rhel-[0-9]{,2}-x86_64.yaml ]]; then
                        continue
                    fi
                elif [[ "$dest" == *"Dockerfile.fedora" ]]; then
                    if ! [[ "$DG_CONF" =~ fedora-[0-9]{,2}-x86_64.yaml ]]; then
                        continue
                    fi
                elif [[ "$dest" == *"Dockerfile" ]]; then
                    if ! [[ "$DG_CONF" =~ centos-[0-9]{,2}-x86_64.yaml ]]; then
                        continue
                    fi
                fi
                prolog="\$(V_DGM)$cdir"
                core_subst=$core
               ;;
            link)
                [[ -z "$link_name" ]] && echo "link_name has to be specified in link rule" && exit 1
                [[ -z "$link_target" ]] && echo "link_target has to be specified in link rule" && exit 1
                dest="$link_name"
                core_subst=$(echo $core | sed -e "s~__link_target__~"${link_target}"~g")
                prolog="\$(V_LN)$cdir"
                ;;
        esac

        case $version$dest$src in
            *' '*) die "space not allowed in version, dest, src" ;;
        esac

        target=$version/$dest
        targets+="\\$nl	$target"

        cat >> auto_targets.mk << EOF
$nl$target: $src manifest.sh
	$prolog \\
	$core_subst${mode:+"; \\
	chmod $mode '\$@'"}
EOF
    done
    IFS=$OLD_IFS
}

for version in ${VERSIONS}; do
    # copy targets
    rules="$COPY_RULES"
    core="cp \$< \$@"
    creator="copy"
    parse_rules
    COPY_TARGETS+="$targets"


    # distgen targets
    rules="$DISTGEN_RULES"
    # TODO: Drop terrible hack that we use fixed --distro here!
    core="\$(DG) --multispec specs/multispec.yml \\
	--template \"\$<\" --distro centos-7-x86_64.yaml \\
	--multispec-selector version=\"$version\" --output \"\$@\""
    creator="distgen"
    parse_rules
    DISTGEN_TARGETS+="$targets"


    rules=$SYMLINK_RULES
    core="ln -fs __link_target__ \$@"
    creator="link"
    parse_rules
    SYMLINK_TARGETS+="$targets"
done

while read -r combination; do
    # line looks like: --distro rhel-7-x86_64.yaml --multispec-selector version=9.4
    eval 'set -- $combination'
    case $4 in
        version=*) version=${4##*=} ;;
        *) die "version not found"
    esac
    case $2 in
        *x86_64*) DG_CONF=$2 ;;
        *) die "invalid --distro option"
    esac
    # distgen multi targets
    rules="$DISTGEN_MULTI_RULES"
    core="\$(DG) --multispec specs/multispec.yml \\
                --template \"\$<\" \\
                --output \"\$@\" \\
                $combination"
    creator="distgen_multi"
    parse_rules
    DISTGEN_MULTI_TARGETS+="$targets"
done <<< "$DISTGEN_COMBINATIONS"

cat -v >> auto_targets.mk <<EOF
COPY_TARGETS = $COPY_TARGETS

DISTGEN_TARGETS = $DISTGEN_TARGETS

DISTGEN_MULTI_TARGETS = $DISTGEN_MULTI_TARGETS

SYMLINK_TARGETS =  $SYMLINK_TARGETS
EOF
