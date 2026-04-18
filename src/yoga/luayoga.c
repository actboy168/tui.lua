#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include "yoga/Yoga.h"

#define FlexDirection 1
#define Justify 2
#define Align 4
#define Wrap 8
#define Display 16
#define PositionType 32
#define Overflow 64
#define BoxSizing 128

#define ENUM(x, what) { YG##x##ToString(YG##x##what), (x) << 16 | (YG##x##what) },

struct enum_string {
	const char * name;
	int value;
};

struct set_number {
	void (*set)(YGNodeRef node, float width);
	void (*setPercent)(YGNodeRef node, float width);
	void (*setAuto)(YGNodeRef node);
	void (*setMaxContent)(YGNodeRef node);
	void (*setFitContent)(YGNodeRef node);
	void (*setStretch)(YGNodeRef node);
};

struct set_edge_number {
	void (*set)(YGNodeRef node, YGEdge edge, float v);
	void (*setPercent)(YGNodeRef node, YGEdge edge, float v);
	void (*setAuto)(YGNodeRef node, YGEdge edge);
};

static int
lnodeNew(lua_State *L) {
	YGNodeRef node = YGNodeNew();
	if (lua_islightuserdata(L, 1)) {
		YGNodeRef parent = lua_touserdata(L, 1);
		size_t n = YGNodeGetChildCount(parent);
		YGNodeInsertChild(parent, node, n);
	}
	lua_pushlightuserdata(L, node);
	return 1;
}

static int
lnodeFree(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	YGNodeFreeRecursive(node);
	return 0;
}

static int
lnodeCalc(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	YGNodeCalculateLayout(node, YGUndefined, YGUndefined, YGDirectionLTR);
	return 0;
}

static int
lnodeGet(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	float r[] = {
		YGNodeLayoutGetLeft(node),
		YGNodeLayoutGetTop(node),
		YGNodeLayoutGetWidth(node),
		YGNodeLayoutGetHeight(node)
	};
	int i;
	for (i=0;i<4;i++) {
		lua_pushinteger(L, (int)r[i]);
	}
	return 4;
}

typedef void (*setfunc)(lua_State *L, YGNodeRef node);

static inline int
is_whitespace(char c) {
	return c =='\0' || c == ' ' || c == '\t';
}

static void
setNumberString(lua_State *L, YGNodeRef node, const char *v, const struct set_number *setter) {
	char* endptr = NULL;
	float number = strtof(v, &endptr);
	if (*endptr == '%') {
		setter->setPercent(node, number);
	} else if (is_whitespace(*endptr)) {
		setter->set(node, number);
	} else if (setter->setAuto && strcmp(v, "auto") == 0) {
		setter->setAuto(node);
	} else if (strcmp(v, "stretch") == 0) {
		setter->setStretch(node);
	} else if (strcmp(v, "max-content") == 0) {
		setter->setMaxContent(node);
	} else if (strcmp(v, "fit-content") == 0) {
		setter->setFitContent(node);
	} else {
		luaL_error(L, "Invalid number %s", v);
	}
}

static void
setNumber(lua_State *L, YGNodeRef node, const struct set_number *setter) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		float v = lua_tonumber(L, -1);
		setter->set(node, v);
	} else {
		const char * v = luaL_checkstring(L, -1);
		setNumberString(L, node, v, setter);
	}
}

static void
lsetWidth(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetWidth,
		YGNodeStyleSetWidthPercent,
		YGNodeStyleSetWidthAuto,
		YGNodeStyleSetWidthMaxContent,
		YGNodeStyleSetWidthFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetMinWidth(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetMinWidth,
		YGNodeStyleSetMinWidthPercent,
		NULL,
		YGNodeStyleSetMinWidthMaxContent,
		YGNodeStyleSetMinWidthFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetMaxWidth(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetMaxWidth,
		YGNodeStyleSetMaxWidthPercent,
		NULL,
		YGNodeStyleSetMaxWidthMaxContent,
		YGNodeStyleSetMaxWidthFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetHeight(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetHeight,
		YGNodeStyleSetHeightPercent,
		YGNodeStyleSetHeightAuto,
		YGNodeStyleSetHeightMaxContent,
		YGNodeStyleSetHeightFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetMinHeight(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetMinHeight,
		YGNodeStyleSetMinHeightPercent,
		NULL,
		YGNodeStyleSetMinHeightMaxContent,
		YGNodeStyleSetMinHeightFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetMaxHeight(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetMaxHeight,
		YGNodeStyleSetMaxHeightPercent,
		NULL,
		YGNodeStyleSetMaxHeightMaxContent,
		YGNodeStyleSetMaxHeightFitContent,
	};
	setNumber(L, node, &setter);
}

static const char *
skip_whitespace(const char *v) {
	while(*v == ' ' || *v == '\t') {
		++v;
	}
	return v;
}

static int
count_words(const char *v) {
	int n = 0;
	do {
		v = skip_whitespace(v);
		if (*v != '\0') {
			++n;
			while (!is_whitespace(*v))
				++v;
		}
	} while (*v != '\0');
	return n;
}

static const char *
setEdgeNumber(lua_State *L, YGNodeRef node, YGEdge edge, const char *v, const struct set_edge_number *setter) {
	v = skip_whitespace(v);
	char* endptr = NULL;
	float number = strtof(v, &endptr);
	if (is_whitespace(*endptr)) {
		setter->set(node, edge, number);
		return endptr;
	} else if (setter->setPercent && *endptr == '%') {
		setter->setPercent(node, edge, number);
		return endptr+1;
	} else if (setter->setAuto && memcmp("auto", v, 4) == 0) {
		if (!is_whitespace(v[4]))
			luaL_error(L, "Invalid number %s", v);
		setter->setAuto(node, edge);
		return v + 4;
	} else {
		luaL_error(L, "Invalid number %s", v);
	}
	return NULL;
}

static void
setFourNumber(lua_State *L, YGNodeRef node, const struct set_edge_number *setter) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		float v = lua_tonumber(L, -1);
		setter->set(node, YGEdgeAll, v);
	} else {
		const char * v = luaL_checkstring(L, -1);
		switch (count_words(v)) {
		case 1:
			setEdgeNumber(L, node, YGEdgeAll, v, setter);
			break;
		case 2:
			v = setEdgeNumber(L, node, YGEdgeVertical, v, setter);
			setEdgeNumber(L, node, YGEdgeHorizontal, v, setter);
			break;
		case 3:
			v = setEdgeNumber(L, node, YGEdgeTop, v, setter);
			v = setEdgeNumber(L, node, YGEdgeHorizontal, v, setter);
			setEdgeNumber(L, node, YGEdgeBottom, v, setter);
			break;
		case 4:
			v = setEdgeNumber(L, node, YGEdgeTop, v, setter);
			v = setEdgeNumber(L, node, YGEdgeEnd, v, setter);
			v = setEdgeNumber(L, node, YGEdgeBottom, v, setter);
			setEdgeNumber(L, node, YGEdgeStart, v, setter);
			break;
		default:
			luaL_error(L, "Invalid numbers %s", v);
		}
	}
}

static void
lsetFlexGrow(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetFlexGrow(node, luaL_checknumber(L, -1));
}

static void
lsetFlexShrink(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetFlexShrink(node, luaL_checknumber(L, -1));
}

static void
lsetFlexBasis(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetFlexBasis,
		YGNodeStyleSetFlexBasisPercent,
		YGNodeStyleSetFlexBasisAuto,
		YGNodeStyleSetFlexBasisMaxContent,
		YGNodeStyleSetFlexBasisFitContent,
	};
	setNumber(L, node, &setter);
}

static void
lsetMargin(lua_State *L, YGNodeRef node) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetMargin,
		YGNodeStyleSetMarginPercent,
		YGNodeStyleSetMarginAuto,
	};
	setFourNumber(L, node, &setter);
}

static void
lsetPadding(lua_State *L, YGNodeRef node) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetPadding,
		YGNodeStyleSetPaddingPercent,
		NULL,
	};
	setFourNumber(L, node, &setter);
}

static void
setPaddingEdge(lua_State *L, YGNodeRef node, YGEdge edge) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetPadding,
		YGNodeStyleSetPaddingPercent,
		NULL,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		setter.set(node, edge, lua_tonumber(L, -1));
	} else {
		setEdgeNumber(L, node, edge, luaL_checkstring(L, -1), &setter);
	}
}

static void lsetPaddingTop(lua_State *L, YGNodeRef node)        { setPaddingEdge(L, node, YGEdgeTop); }
static void lsetPaddingBottom(lua_State *L, YGNodeRef node)     { setPaddingEdge(L, node, YGEdgeBottom); }
static void lsetPaddingLeft(lua_State *L, YGNodeRef node)       { setPaddingEdge(L, node, YGEdgeLeft); }
static void lsetPaddingRight(lua_State *L, YGNodeRef node)      { setPaddingEdge(L, node, YGEdgeRight); }
static void lsetPaddingX(lua_State *L, YGNodeRef node) { setPaddingEdge(L, node, YGEdgeHorizontal); }
static void lsetPaddingY(lua_State *L, YGNodeRef node) { setPaddingEdge(L, node, YGEdgeVertical); }

static void
setMarginEdge(lua_State *L, YGNodeRef node, YGEdge edge) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetMargin,
		YGNodeStyleSetMarginPercent,
		YGNodeStyleSetMarginAuto,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		setter.set(node, edge, lua_tonumber(L, -1));
	} else {
		setEdgeNumber(L, node, edge, luaL_checkstring(L, -1), &setter);
	}
}

static void lsetMarginTop(lua_State *L, YGNodeRef node)        { setMarginEdge(L, node, YGEdgeTop); }
static void lsetMarginBottom(lua_State *L, YGNodeRef node)     { setMarginEdge(L, node, YGEdgeBottom); }
static void lsetMarginLeft(lua_State *L, YGNodeRef node)       { setMarginEdge(L, node, YGEdgeLeft); }
static void lsetMarginRight(lua_State *L, YGNodeRef node)      { setMarginEdge(L, node, YGEdgeRight); }
static void lsetMarginX(lua_State *L, YGNodeRef node) { setMarginEdge(L, node, YGEdgeHorizontal); }
static void lsetMarginY(lua_State *L, YGNodeRef node) { setMarginEdge(L, node, YGEdgeVertical); }

static void
lsetBorder(lua_State *L, YGNodeRef node) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetBorder,
		NULL,
		NULL,
	};
	setFourNumber(L, node, &setter);
}

static void
setBorderEdge(lua_State *L, YGNodeRef node, YGEdge edge) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetBorder(node, edge, lua_tonumber(L, -1));
	} else {
		luaL_error(L, "border edge expects a number");
	}
}

static void lsetBorderTop(lua_State *L, YGNodeRef node)    { setBorderEdge(L, node, YGEdgeTop); }
static void lsetBorderBottom(lua_State *L, YGNodeRef node) { setBorderEdge(L, node, YGEdgeBottom); }
static void lsetBorderLeft(lua_State *L, YGNodeRef node)   { setBorderEdge(L, node, YGEdgeLeft); }
static void lsetBorderRight(lua_State *L, YGNodeRef node)  { setBorderEdge(L, node, YGEdgeRight); }

static void
lsetAspectRatio(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetAspectRatio(node, luaL_checknumber(L, -1));
}

static void
lsetOverflow(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetOverflow(node, getEnum(L, Overflow, "overflow"));
}

static void
lsetBoxSizing(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetBoxSizing(node, getEnum(L, BoxSizing, "boxSizing"));
}

static void
lsetGap(lua_State *L, YGNodeRef node) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetGap(node, YGGutterAll, lua_tonumber(L, -1));
	} else {
		luaL_error(L, "gap expects a number");
	}
}

static void
lsetRowGap(lua_State *L, YGNodeRef node) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetGap(node, YGGutterRow, lua_tonumber(L, -1));
	} else {
		luaL_error(L, "rowGap expects a number");
	}
}

static void
lsetColumnGap(lua_State *L, YGNodeRef node) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetGap(node, YGGutterColumn, lua_tonumber(L, -1));
	} else {
		luaL_error(L, "columnGap expects a number");
	}
}

static int
getEnum(lua_State *L, int type, const char *pname) {
	lua_pushvalue(L, -1);
	if (lua_rawget(L, lua_upvalueindex(2)) == LUA_TNUMBER) {
		int v = lua_tointeger(L, -1);
		if (((v >> 16) & type) == type) {
			v &= 0xffff;
			return v;
		}
	}
	return luaL_error(L, "Invalid enum %s for %s", luaL_tolstring(L, -2, NULL), pname);
}

static int
getEnumHigh(lua_State *L, int type, const char *pname) {
	int e = getEnum(L, type, pname);
	return e >> 8;
}

static int
getEnumLow(lua_State *L, int type, const char *pname) {
	int e = getEnum(L, type, pname);
	return e & 0xff;
}

static void
lsetFlexDirection(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetFlexDirection(node, getEnum(L, FlexDirection, "flex-direction"));
}

static void
lsetJustifyContent(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetJustifyContent(node, getEnumHigh(L, Justify, "justify-content"));
}

static void
lsetAlignItems(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetAlignItems(node, getEnumLow(L, Align, "align-items"));
}

static void
lsetAlignContent(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetAlignContent(node, getEnumLow(L, Align, "align-content"));
}

static void
lsetAlignSelf(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetAlignSelf(node, getEnumLow(L, Align, "align-self"));
}

static void
lsetFlexWrap(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetFlexWrap(node, getEnum(L, Wrap, "wrap"));
}

static void
lsetDisplay(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetDisplay(node, getEnum(L, Display, "display"));
}

static void
lsetPosition(lua_State *L, YGNodeRef node) {
	YGNodeStyleSetPositionType(node, getEnum(L, PositionType, "position"));
}

static void
setPosition(lua_State *L, YGNodeRef node, YGEdge edge) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetPosition,
		YGNodeStyleSetPositionPercent,
		YGNodeStyleSetPositionAuto,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		float v = luaL_checknumber(L, -1);
		setter.set(node, edge, v);
	} else {
		const char *v = luaL_checkstring(L, -1);
		setEdgeNumber(L, node, edge, v, &setter);
	}
}


static void
lsetTop(lua_State *L, YGNodeRef node) {
	setPosition(L, node, YGEdgeTop);
}

static void
lsetBottom(lua_State *L, YGNodeRef node) {
	setPosition(L, node, YGEdgeBottom);
}

static void
lsetLeft(lua_State *L, YGNodeRef node) {
	setPosition(L, node, YGEdgeLeft);
}

static void
lsetRight(lua_State *L, YGNodeRef node) {
	setPosition(L, node, YGEdgeRight);
}

static int
lnodeSet(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_pushnil(L);
	int top = lua_gettop(L);
	while (lua_next(L, 2) != 0) {
		lua_pushvalue(L, -2);
		if (lua_rawget(L, lua_upvalueindex(1)) == LUA_TLIGHTUSERDATA) {
			setfunc func = (setfunc)lua_touserdata(L, -1);
			lua_pop(L, 1);
			func(L, node);
		} else {
			lua_pop(L, 1);
			luaL_error(L, "Unknown yoga prop %s", luaL_tolstring(L, -1, NULL));
		}
		lua_settop(L, top);
	}
	return 0;
}

LUAMOD_API int
luaopen_yoga(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "node_new", lnodeNew },
		{ "node_free", lnodeFree },
		{ "node_calc", lnodeCalc },
		{ "node_get", lnodeGet },
		{ "node_set", NULL },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	
	struct {
		const char *name;
		setfunc func;
	} setter [] = {
		{ "width", lsetWidth },
		{ "height", lsetHeight },
		{ "minWidth", lsetMinWidth },
		{ "maxWidth", lsetMaxWidth },
		{ "minHeight", lsetMinHeight },
		{ "maxHeight", lsetMaxHeight },
		{ "flexDirection", lsetFlexDirection },
		{ "justifyContent", lsetJustifyContent },
		{ "alignItems", lsetAlignItems },
		{ "alignContent", lsetAlignContent },
		{ "alignSelf", lsetAlignSelf },
		{ "margin", lsetMargin },
		{ "marginTop", lsetMarginTop },
		{ "marginBottom", lsetMarginBottom },
		{ "marginLeft", lsetMarginLeft },
		{ "marginRight", lsetMarginRight },
		{ "marginX", lsetMarginX },
		{ "marginY", lsetMarginY },
		{ "padding", lsetPadding },
		{ "paddingTop", lsetPaddingTop },
		{ "paddingBottom", lsetPaddingBottom },
		{ "paddingLeft", lsetPaddingLeft },
		{ "paddingRight", lsetPaddingRight },
		{ "paddingX", lsetPaddingX },
		{ "paddingY", lsetPaddingY },
		{ "border", lsetBorder },
		{ "borderTop", lsetBorderTop },
		{ "borderBottom", lsetBorderBottom },
		{ "borderLeft", lsetBorderLeft },
		{ "borderRight", lsetBorderRight },
		{ "gap", lsetGap },
		{ "rowGap", lsetRowGap },
		{ "columnGap", lsetColumnGap },
		{ "flexWrap", lsetFlexWrap },
		{ "flexGrow", lsetFlexGrow },
		{ "flexShrink", lsetFlexShrink },
		{ "flexBasis", lsetFlexBasis },
		{ "aspectRatio", lsetAspectRatio },
		{ "overflow", lsetOverflow },
		{ "boxSizing", lsetBoxSizing },
		{ "display", lsetDisplay },
		{ "position", lsetPosition },
		{ "top", lsetTop },
		{ "bottom", lsetBottom },
		{ "left", lsetLeft },
		{ "right", lsetRight },
	};
	int n = sizeof(setter) / sizeof(setter[0]);
	int i;
	lua_createtable(L, n, 0);
	for (i=0;i<n;i++) {
		lua_pushlightuserdata(L, (void *)setter[i].func);
		lua_setfield(L, -2, setter[i].name);
	}

	struct enum_string	estr[] = {
		ENUM(FlexDirection, Column)
		ENUM(FlexDirection, ColumnReverse)
		ENUM(FlexDirection, Row)
		ENUM(FlexDirection, RowReverse)
		ENUM(Justify, FlexStart)
		ENUM(Justify, Center)
		ENUM(Justify, FlexEnd)
		ENUM(Justify, SpaceBetween)
		ENUM(Justify, SpaceAround)
		ENUM(Justify, SpaceEvenly)
		ENUM(Align, Auto)
		ENUM(Align, FlexStart)
		ENUM(Align, Center)
		ENUM(Align, FlexEnd)
		ENUM(Align, Baseline)
		ENUM(Align, SpaceBetween)
		ENUM(Align, SpaceAround)
		ENUM(Align, SpaceEvenly)
		ENUM(Align, Stretch)
		ENUM(Wrap, NoWrap)
		ENUM(Wrap, Wrap)
		ENUM(Wrap, WrapReverse)
		ENUM(Display, Flex)
		ENUM(Display, None)
		ENUM(Display, Contents)
		ENUM(PositionType, Static)
		ENUM(PositionType, Relative)
		ENUM(PositionType, Absolute)
		ENUM(Overflow, Visible)
		ENUM(Overflow, Hidden)
		ENUM(Overflow, Scroll)
		ENUM(BoxSizing, BorderBox)
		ENUM(BoxSizing, ContentBox)
	};
	n = sizeof(estr) / sizeof(estr[0]);
	lua_createtable(L, n, 0);
	for (i=0;i<n;i++) {
		int v = 0;
		if (lua_getfield(L, -1, estr[i].name) == LUA_TNUMBER) {
			v = lua_tointeger(L, -1);
			v = (v & ~0xffff) | ((v & 0xff) << 8);
		}
		lua_pop(L, 1);
		// align use high 8bits
		lua_pushinteger(L, estr[i].value | v);
		lua_setfield(L, -2, estr[i].name);
	}
	lua_pushcclosure(L, lnodeSet, 2);
	lua_setfield(L, -2, "node_set");

	// Set PointScaleFactor=1 on default config so all Yoga nodes produce
	// integer coordinates (TUI is cell-based; fractional positions like
	// \27[73.0;3.0H are rejected by terminals).
	YGConfigSetPointScaleFactor(YGConfigGetDefault(), 1.0f);

	return 1;
}
