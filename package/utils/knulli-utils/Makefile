# Software Name
TARGET = progressbar

#CROSS_COMPILE = /opt/cdata/plusrg35xx/knulli/distribution/output/h700/host/bin/aarch64-buildroot-linux-gnu-
CROSS_COMPILE = /opt/cdata/knulli/new_distribution/output/rk3566/host/bin/aarch64-buildroot-linux-gnu-

# Compiler
CC = $(CROSS_COMPILE)g++
LINKER   = $(CROSS_COMPILE) g++
CFLAGS = -fdata-sections -ffunction-sections -fPIC -flto -Wall -D_RG28XX_
#-Ofast
LIBS += -lSDL2 -lSDL2_image -lSDL2_ttf -lSDL2_gfx -lz -lpthread -lm # -lasound

# You can use Ofast too but it can be more prone to bugs, careful.
CFLAGS += -g -Iinclude/ -DTRIPLE_BUFFER=1
LDFLAGS = -Wl,--start-group $(LIBS) -Wl,--end-group -Wl,--as-needed -Wl,--gc-sections -flto

DEBUG = YES

SRCDIR = src
OBJDIR = obj
BINDIR = output
SOURCES := $(wildcard $(SRCDIR)/*.cpp)

OBJECTS := $(patsubst $(SRCDIR)/%.cpp,$(OBJDIR)/%.o,$(SOURCES))
OBJECTS := $(patsubst $(SRCDIR)/%.c,$(OBJDIR)/%.o,$(OBJECTS))

rm = rm -f

all: clean remove prepare $(BINDIR)/$(TARGET) $(OBJECTS)

prepare:
	mkdir -p $(BINDIR)
	mkdir -p $(OBJDIR)

$(BINDIR)/$(TARGET): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) $(LIBS) -o $@
	@echo "Linking complete!"

$(OBJECTS): $(OBJDIR)/%.o: $(SRCDIR)/%.cpp
	$(CC) $(CFLAGS) -c $< -o $@
	@echo "Compiled "$<" successfully!"

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@
	@echo "Compiled "$<" successfully!"

.PHONY: clean
clean:
	$(rm) $(OBJECTS)
	@echo "Cleanup complete!"

.PHONY: remove
remove: clean
	$(rm) $(BINDIR)/$(TARGET)
	@echo "Executable removed!"
