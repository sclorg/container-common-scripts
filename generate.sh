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

test -f auto_targets.mk && rm auto_targets.mk

DESTDIR="${DESTDIR:-$PWD}"

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

        case "$creator" in
            copy)
                [[ -z "$src" ]] && echo "src has to be specified in copy rule" && exit 1
                [[ -z "$dest" ]] && echo "dest has to be specified in copy rule" && exit 1
                core_subst=$core
                ;;
            distgen)
                [[ -z "$src" ]] && echo "src has to be specified in distgen rule" && exit 1
                [[ -z "$dest" ]] && echo "dest has to be specified in distgen rule" && exit 1
                core_subst=$core
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
                core_subst=$core
               ;;
            link)
                [[ -z "$link_name" ]] && echo "link_name has to be specified in link rule" && exit 1
                [[ -z "$link_target" ]] && echo "link_target has to be specified in link rule" && exit 1
                dest="$link_name"
                core_subst=$(echo $core | sed -e "s~__link_target__~"${link_target}"~g")
                ;;
        esac
        t=$(echo ${DESTDIR}/${version}/${dest} | sed 's/ /\\ /g')
        src=$(echo $src | sed 's/ /\\ /g' )
        targets+="	$t \\
"
        cat >> auto_targets.mk << EOF
$t: $src manifest.sh
	@echo ${message} ; \\
	mkdir -p "\$\$(dirname \$@)" || exit 1 ; \\
	${core_subst}
    ${mode:+"chmod ${mode} "\$@""}

EOF
    done
    IFS=$OLD_IFS
}

for version in ${VERSIONS}; do
    # copy targets
    rules="$COPY_RULES"
    core="cp \$< \$@ ; \\"
    message="Copying \"\$@\""
    creator="copy"
    parse_rules
    COPY_TARGETS+="$targets"


    # distgen targets
    rules="$DISTGEN_RULES"
    # TODO: Drop terrible hack that we use fixed --distro here!
    core="\$(DG) --multispec specs/multispec.yml \\
	--template \"\$<\" --distro centos-7-x86_64.yaml \\
	--multispec-selector version=\"$version\" --output \"\$@\" ; \\"
    message="Generating \"\$@\" using distgen"
    creator="distgen"
    parse_rules
    DISTGEN_TARGETS+="$targets"


    rules=$SYMLINK_RULES
    core="ln -fs __link_target__ \$@ ; \\"
    message="Creating symlink \"\$@\""
    creator="link"
    parse_rules
    SYMLINK_TARGETS+="$targets"
done

while read -r combination; do
    version=${combination##*=}
    DG_CONF=$(echo $combination | cut -d' ' -f2)
    # distgen multi targets
    rules="$DISTGEN_MULTI_RULES"
    core="\$(DG) --multispec specs/multispec.yml \\
                --template \"\$<\" \\
                --output \"\$@\" \\
                $combination ; \\"
    message="Generating \"\$@\" using distgen"
    creator="distgen_multi"
    parse_rules
    DISTGEN_MULTI_TARGETS+="$targets"
done <<< ${DISTGEN_COMBINATIONS}

    # adding COPY_TARGETS variable at the bottom of auto_targets.mk file
    cat -v >> auto_targets.mk << EOF
COPY_TARGETS = \\
$COPY_TARGETS
EOF

    # adding DISTGEN_TARGETS variable at the bottom of auto_targets.mk file
    cat -v >> auto_targets.mk << EOF
DISTGEN_TARGETS = \\
$DISTGEN_TARGETS
EOF

    # adding DISTGEN_MULTI_TARGETS variable at the bottom of auto_targets.mk file
    cat -v >> auto_targets.mk << EOF
DISTGEN_MULTI_TARGETS = \\
$DISTGEN_MULTI_TARGETS
EOF

    cat -v >> auto_targets.mk << EOF
SYMLINK_TARGETS = \\
$SYMLINK_TARGETS
EOF
