# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

EMOJI = NotoColorEmoji
EMOJI_WINDOWS = NotoColorEmoji_WindowsCompatible
all: $(EMOJI).ttf $(EMOJI_WINDOWS).ttf

CFLAGS = -std=c99 -Wall -Wextra `pkg-config --cflags --libs cairo`
LDFLAGS = -lm `pkg-config --libs cairo`

PNGQUANT = pngquant
PYTHON = python3
PNGQUANTFLAGS = --speed 1 --skip-if-larger --quality 85-95 --force
BODY_DIMENSIONS = 170x160
IMOPS := -size $(BODY_DIMENSIONS) canvas:none -compose copy -gravity center

ZOPFLIPNG = zopflipng
TTX = ttx

EMOJI_BUILDER = third_party/color_emoji/emoji_builder.py
# flag for emoji builder.  Default to legacy small metrics for the time being.
SMALL_METRICS := -S
ADD_GLYPHS = add_glyphs.py
ADD_GLYPHS_FLAGS = -a emoji_aliases.txt
PUA_ADDER = map_pua_emoji.py
VS_ADDER = add_vs_cmap.py # from nototools

EMOJI_SRC_DIR ?= png/160

SEQUENCE_CHECK_PY = check_emoji_sequences.py
BYPASS_SEQUENCE_CHECK = 'True'

BUILD_DIR := build
EMOJI_DIR := $(BUILD_DIR)/emoji
QUANTIZED_DIR := $(BUILD_DIR)/quantized_pngs
COMPRESSED_DIR := $(BUILD_DIR)/compressed_pngs

ifeq (,$(shell which $(ZOPFLIPNG)))
  ifeq (,$(wildcard $(ZOPFLIPNG)))
    MISSING_ZOPFLI = fail
  endif
endif

ifndef VIRTUAL_ENV
  MISSING_VENV = fail
endif

ifeq (, $(shell which $(VS_ADDER)))
  MISSING_PY_TOOLS = fail
endif
ifeq (, $(shell which $(TTX)))
  MISSING_PY_TOOLS = fail
endif

EMOJI_NAMES = $(notdir $(wildcard $(EMOJI_SRC_DIR)/emoji_u*.png))
EMOJI_FILES= $(addprefix $(EMOJI_DIR)/,$(EMOJI_NAMES)))

ALL_NAMES = $(EMOJI_NAMES)

ALL_QUANTIZED_FILES = $(addprefix $(QUANTIZED_DIR)/, $(ALL_NAMES))
ALL_COMPRESSED_FILES = $(addprefix $(COMPRESSED_DIR)/, $(ALL_NAMES))


emoji: $(EMOJI_FILES)

quantized: $(ALL_QUANTIZED_FILES)

compressed: $(ALL_COMPRESSED_FILES)

check_tools:
ifdef MISSING_ZOPFLI
	$(error "Missing $(ZOPFLIPNG). Try 'brew install zopfli' (Mac) or 'sudo apt-get install zopfli' (linux)")
endif
ifdef MISSING_VENV
		$(error "Please start your virtual environment, and run: "'pip install -r requirements.txt'")
endif
ifdef MISSING_PY_TOOLS
		$(error "Missing tools; run: "'pip install -r requirements.txt' in your virtual environment")
endif

$(EMOJI_DIR) $(QUANTIZED_DIR) $(COMPRESSED_DIR):
	mkdir -p "$@"


# imagemagick's -extent operator munges the grayscale images in such a fashion
# that while it can display them correctly using libpng12, chrome and gimp using
# both libpng12 and libpng16 display the wrong gray levels.
#
# @convert "$<" -gravity center -background none -extent 136x128 "$@"
#
# We can get around the conversion to a gray colorspace in the version of
# imagemagick packaged with ubuntu trusty (6.7.7-10) by using -composite.

$(EMOJI_DIR)/%.png: $(EMOJI_SRC_DIR)/%.png | $(EMOJI_DIR)
	@convert $(IMOPS) "$<" -composite "PNG32:$@"

$(QUANTIZED_DIR)/%.png: $(EMOJI_DIR)/%.png | $(QUANTIZED_DIR)
	@($(PNGQUANT) $(PNGQUANTFLAGS) -o "$@" "$<"; case "$$?" in "98"|"99") echo "reuse $<";cp $< $@;; *) exit "$$?";; esac)

$(COMPRESSED_DIR)/%.png: $(QUANTIZED_DIR)/%.png | check_tools $(COMPRESSED_DIR)
	@$(ZOPFLIPNG) -y "$<" "$@" 1> /dev/null 2>&1

# Make 3.81 can endless loop here if the target is missing but no
# prerequisite is updated and make has been invoked with -j, e.g.:
# File `font' does not exist.
#      File `NotoColorEmoji.tmpl.ttx' does not exist.
# File `font' does not exist.
#      File `NotoColorEmoji.tmpl.ttx' does not exist.
# ...
# Run make without -j if this happens.

$(EMOJI).tmpl.ttx: $(EMOJI).tmpl.ttx.tmpl $(ADD_GLYPHS) $(ALL_COMPRESSED_FILES)
	$(PYTHON) $(ADD_GLYPHS) -f "$<" -o "$@" -d "$(COMPRESSED_DIR)" $(ADD_GLYPHS_FLAGS)

$(EMOJI_WINDOWS).tmpl.ttx: $(EMOJI).tmpl.ttx.tmpl $(ADD_GLYPHS) $(ALL_COMPRESSED_FILES)
	$(PYTHON) $(ADD_GLYPHS) --add_cmap4 --add_glyf -f "$<" -o "$@" -d "$(COMPRESSED_DIR)" $(ADD_GLYPHS_FLAGS)

%.ttf: %.ttx
	@rm -f "$@"
	ttx "$<"

$(EMOJI).ttf: check_sequence $(EMOJI).tmpl.ttf $(EMOJI_BUILDER) $(PUA_ADDER) \
	$(ALL_COMPRESSED_FILES) | check_tools

	@$(PYTHON) $(EMOJI_BUILDER) $(SMALL_METRICS) -V $(word 2,$^) "$@" "$(COMPRESSED_DIR)/emoji_u"
	@$(PYTHON) $(PUA_ADDER) "$@" "$@-with-pua"
	@$(VS_ADDER) -vs 2640 2642 2695 --dstdir '.' -o "$@-with-pua-varsel" "$@-with-pua"
	@mv "$@-with-pua-varsel" "$@"
	@rm "$@-with-pua"

$(EMOJI_WINDOWS).ttf: check_sequence $(EMOJI_WINDOWS).tmpl.ttf $(EMOJI_BUILDER) $(PUA_ADDER) \
	$(ALL_COMPRESSED_FILES) | check_tools

	@$(PYTHON) $(EMOJI_BUILDER) -O $(SMALL_METRICS) -V $(word 2,$^) "$@" "$(COMPRESSED_DIR)/emoji_u"
	@$(PYTHON) $(PUA_ADDER) "$@" "$@-with-pua"
	@$(VS_ADDER) -vs 2640 2642 2695 --dstdir '.' -o "$@-with-pua-varsel" "$@-with-pua"
	@mv "$@-with-pua-varsel" "$@"
	@rm "$@-with-pua"


check_sequence:
ifdef BYPASS_SEQUENCE_CHECK
	@echo Bypassing the emoji sequence checks
else
	@$(PYTHON) $(SEQUENCE_CHECK_PY) -n $(ALL_NAMES) -c
endif

clean:
	rm -f $(EMOJI).ttf $(EMOJI_WINDOWS).ttf $(EMOJI).tmpl.ttf $(EMOJI_WINDOWS).tmpl.ttf $(EMOJI).tmpl.ttx $(EMOJI_WINDOWS).tmpl.ttx
	rm -f waveflag
	rm -rf $(BUILD_DIR)

.SECONDARY: $(EMOJI_FILES) \
  $(ALL_QUANTIZED_FILES) $(ALL_COMPRESSED_FILES)

.PHONY:	clean flags emoji renamed_flags quantized compressed check_tools

