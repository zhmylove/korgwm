# Release checklist for X11::XCB

## Verification

- make distclean
- update all the documentation
- update VERSION
- update copyright years
- git status                        # check all the changed files
- vim Changes                       # prepare changelog
- perl Makefile.PL
- make manifest
- make dist
- make disttest

## Actual release

- make distclean
- rm \*.gz
- git status
- git add Changes
- git commit -sm 'Release X.X'
- git tag X.X
- git push origin
- git push origin tag X.X
- perl Makefile.PL
- make manifest
- make dist
- make disttest
- upload to CPAN
- give it some time to index on MetaCPAN
- update FreeBSD port and AUR package
