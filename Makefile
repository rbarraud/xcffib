GEN=./dist/build/xcffibgen/xcffibgen
AUTOPEP8=autopep8 --in-place --aggressive --aggressive

XCBDIR?=$(shell pkg-config --variable=xcbincludedir xcb-proto)
ifneq ($(XCBDIR),$(shell pkg-config --variable=xcbincludedir xcb-proto))
	XCBVER=$(shell sed -e '1,/AC_INIT/d' $(XCBDIR)/../configure.ac | head -n 1 | tr -d ,[:blank:])
else
	XCBVER=$(shell pkg-config --modversion xcb-proto)
endif
NCPUS=$(shell grep -c processor /proc/cpuinfo)
PARALLEL=$(shell which parallel)
CABAL=cabal --config-file=/dev/null

# you should have xcb-proto installed to run this
xcffib: $(GEN) module/*.py
	$(GEN) --input $(XCBDIR) --output ./xcffib
	cp ./module/*py ./xcffib/
	sed -i "s/__xcb_proto_version__ = .*/__xcb_proto_version__ = \"${XCBVER}\"/" xcffib/__init__.py
	@if [ "$(TRAVIS)" = true ]; then python xcffib/ffi_build.py; else python xcffib/ffi_build.py > /dev/null 2>&1 || python3 xcffib/ffi_build.py; fi

.PHONY: xcffib-fmt
xcffib-fmt: $(GEN) module/*.py
ifeq (${PARALLEL},)
	$(AUTOPEP8) ./xcffib/*.py
else
	find ./xcffib/*.py | parallel -j $(NCPUS) $(AUTOPEP8) '{}'
endif

dist:
	$(CABAL) configure --enable-tests

.PHONY: $(GEN)
$(GEN): dist
	$(CABAL) build

.PHONY: clean
clean:
	-$(CABAL) clean
	-rm -rf xcffib
	-rm -rf module/*pyc module/__pycache__
	-rm -rf test/*pyc test/__pycache__
	-rm -rf build *egg* *deb .pybuild
	-rm -rf .pc

# A target for just running nosetests. Travis will run 'check', which does
# everything. (Additionally, travis uses separate environments where nosetests
# points to The Right Thing for each, so we don't need to do nosetests3.)
pycheck: xcffib
	nosetests -d
	nosetests3 -d

valgrind: xcffib
	valgrind --leak-check=full --show-leak-kinds=definite nosetests -d

newtests: $(GEN)
	$(GEN) --input ./test/generator/ --output ./test/generator/
	git diff test

# These are all split out so make -j3 check goes as fast as possible.
.PHONY: lint
lint:
	flake8 --config=./test/flake8.cfg ./module

.PHONY: htests
htests: $(GEN)
	$(CABAL) test

check: xcffib lint htests
	nosetests -d -v

deb:
	git buildpackage --git-upstream-tree=master
	lintian

deb-src:
	git buildpackage --git-upstream-tree=master -S

# make release ver=0.99.99
release: xcffib
ifeq (${ver},)
	@echo "no version (ver=) specified, not releasing."
else ifneq ($(wildcard ./xcffib.egg-info*),)
	@echo "xcffib.egg-info exists, not releasing."
else
	sed -i "s/version = .*/version = \"${ver}\"/" setup.py
	sed -i "s/__version__ = .*/__version__ = \"${ver}\"/" xcffib/__init__.py
	sed -r -i -e "s/(^version = \s*)[\"0-9\.]*/\1\"${ver}\"/" setup.py
	sed -r -i -e "s/(^version:\s*)[0-9\.]*/\1${ver}/" xcffib.cabal
	git commit -a -m "Release v${ver}"
	git tag v${ver}
	python setup.py sdist
	python setup.py sdist upload
	cabal sdist
	cabal upload --publish dist/xcffib-${ver}.tar.gz
endif
