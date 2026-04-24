#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "yoga/Yoga.h"

#if defined(__GNUC__)
#define DLL_EXPORT __attribute__((visibility("default")))
#else
#define DLL_EXPORT
#endif

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
	void (*setAuto)(YGNodeRef node);
	void (*setMaxContent)(YGNodeRef node);
	void (*setFitContent)(YGNodeRef node);
	void (*setStretch)(YGNodeRef node);
};

struct set_edge_number {
	void (*set)(YGNodeRef node, YGEdge edge, float v);
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
	long number = strtol(v, &endptr, 10);
	if (is_whitespace(*endptr)) {
		setter->set(node, (float)number);
	} else if (setter->setAuto && strcmp(v, "auto") == 0) {
		setter->setAuto(node);
	} else if (strcmp(v, "stretch") == 0) {
		setter->setStretch(node);
	} else if (strcmp(v, "max-content") == 0) {
		setter->setMaxContent(node);
	} else if (strcmp(v, "fit-content") == 0) {
		setter->setFitContent(node);
	} else {
		luaL_error(L, "Invalid integer %s", v);
	}
}

static void
setNumber(lua_State *L, YGNodeRef node, const struct set_number *setter) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		setter->set(node, (float)v);
	} else {
		const char * v = luaL_checkstring(L, -1);
		setNumberString(L, node, v, setter);
	}
}

static void
lsetWidth(lua_State *L, YGNodeRef node) {
	static const struct set_number setter = {
		YGNodeStyleSetWidth,
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
	long number = strtol(v, &endptr, 10);
	if (is_whitespace(*endptr)) {
		setter->set(node, edge, (float)number);
		return endptr;
	} else if (setter->setAuto && memcmp("auto", v, 4) == 0) {
		if (!is_whitespace(v[4]))
			luaL_error(L, "Invalid number %s", v);
		setter->setAuto(node, edge);
		return v + 4;
	} else {
		luaL_error(L, "Invalid integer %s", v);
	}
	return NULL;
}

static void
setFourNumber(lua_State *L, YGNodeRef node, const struct set_edge_number *setter) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		setter->set(node, YGEdgeAll, (float)v);
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
			luaL_error(L, "Invalid integers %s", v);
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
		YGNodeStyleSetMarginAuto,
	};
	setFourNumber(L, node, &setter);
}

static void
lsetPadding(lua_State *L, YGNodeRef node) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetPadding,
		NULL,
	};
	setFourNumber(L, node, &setter);
}

static void
setPaddingEdge(lua_State *L, YGNodeRef node, YGEdge edge) {
	static const struct set_edge_number setter = {
		YGNodeStyleSetPadding,
		NULL,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		setter.set(node, edge, (float)v);
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
		YGNodeStyleSetMarginAuto,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		setter.set(node, edge, (float)v);
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
	};
	setFourNumber(L, node, &setter);
}

static void
setBorderEdge(lua_State *L, YGNodeRef node, YGEdge edge) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		YGNodeStyleSetBorder(node, edge, (float)v);
	} else {
		luaL_error(L, "border edge expects an integer");
	}
}

static int getEnum(lua_State *L, int type, const char *pname);

static void lsetBorderTop(lua_State *L, YGNodeRef node)    { setBorderEdge(L, node, YGEdgeTop); }
static void lsetBorderBottom(lua_State *L, YGNodeRef node) { setBorderEdge(L, node, YGEdgeBottom); }
static void lsetBorderLeft(lua_State *L, YGNodeRef node)   { setBorderEdge(L, node, YGEdgeLeft); }
static void lsetBorderRight(lua_State *L, YGNodeRef node)  { setBorderEdge(L, node, YGEdgeRight); }

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
		YGNodeStyleSetGap(node, YGGutterAll, (float)luaL_checkinteger(L, -1));
	} else {
		luaL_error(L, "gap expects a number");
	}
}

static void
lsetRowGap(lua_State *L, YGNodeRef node) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetGap(node, YGGutterRow, (float)luaL_checkinteger(L, -1));
	} else {
		luaL_error(L, "rowGap expects a number");
	}
}

static void
lsetColumnGap(lua_State *L, YGNodeRef node) {
	if (lua_type(L, -1) == LUA_TNUMBER) {
		YGNodeStyleSetGap(node, YGGutterColumn, (float)luaL_checkinteger(L, -1));
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
		YGNodeStyleSetPositionAuto,
	};
	if (lua_type(L, -1) == LUA_TNUMBER) {
		int v = luaL_checkinteger(L, -1);
		setter.set(node, edge, (float)v);
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

// --- node_set_box_props / node_set_text_props helpers ---

// Named-key edge expansion for padding/margin tables like { left=1, right=2 }.
// If the table has any named keys, expand them and return true (caller should
// pop the table and skip the scalar setter).  Otherwise return false.
struct named_edge { const char *key; setfunc fn; };
static const struct named_edge padding_edges[] = {
	{ "top",    lsetPaddingTop    },
	{ "bottom", lsetPaddingBottom },
	{ "left",   lsetPaddingLeft   },
	{ "right",  lsetPaddingRight  },
	{ "x",      lsetPaddingX      },
	{ "y",      lsetPaddingY      },
};
static const struct named_edge margin_edges[] = {
	{ "top",    lsetMarginTop    },
	{ "bottom", lsetMarginBottom },
	{ "left",   lsetMarginLeft   },
	{ "right",  lsetMarginRight  },
	{ "x",      lsetMarginX      },
	{ "y",      lsetMarginY      },
};

static int
expand_named_edges(lua_State *L, YGNodeRef node, int tbl, const struct named_edge *edges, int n) {
	int expanded = 0;
	for (int i = 0; i < n; i++) {
		if (lua_getfield(L, tbl, edges[i].key) != LUA_TNIL) {
			edges[i].fn(L, node);
			expanded = 1;
		}
		lua_pop(L, 1);
	}
	return expanded;
}

// coerce_table_to_string: replace the table at stack position tbl with "v1 v2 ..." string.
// Used so margin={1,2} can be passed as the string "1 2" to setFourNumber.
// Returns 1 if the table was expanded via named keys (caller pops the table),
// or 0 if it was coerced to a string (caller proceeds with scalar setter).
static int
coerce_or_expand_table(lua_State *L, int tbl, YGNodeRef node, const char *prop_key) {
	// Check for named keys first (padding/margin only).
	if (strcmp(prop_key, "padding") == 0) {
		if (expand_named_edges(L, node, tbl, padding_edges,
				(int)(sizeof(padding_edges)/sizeof(padding_edges[0]))))
			return 1;
	} else if (strcmp(prop_key, "margin") == 0) {
		if (expand_named_edges(L, node, tbl, margin_edges,
				(int)(sizeof(margin_edges)/sizeof(margin_edges[0]))))
			return 1;
	}
	// Array-style table: coerce to "v1 v2 ..." string.
	luaL_Buffer b;
	luaL_buffinit(L, &b);
	for (int j = 1; ; j++) {
		lua_rawgeti(L, tbl, j);
		if (lua_type(L, -1) == LUA_TNIL) { lua_pop(L, 1); break; }
		if (j > 1) luaL_addchar(&b, ' ');
		size_t len;
		const char *s = lua_tolstring(L, -1, &len);
		if (s) luaL_addlstring(&b, s, len);
		lua_pop(L, 1);
	}
	luaL_pushresult(&b);
	lua_replace(L, tbl);
	return 0;
}

// Static setter array for all box-layout props (matches layout.lua's PASSTHROUGH_KEYS
// plus borderStyle special-casing).  Upvalue 2 = enum table (same as lnodeSet).
static const struct { const char *key; setfunc fn; } box_setter_list[] = {
	{ "width",          lsetWidth          },
	{ "height",         lsetHeight         },
	{ "minWidth",       lsetMinWidth       },
	{ "maxWidth",       lsetMaxWidth       },
	{ "minHeight",      lsetMinHeight      },
	{ "maxHeight",      lsetMaxHeight      },
	{ "flexGrow",       lsetFlexGrow       },
	{ "flexShrink",     lsetFlexShrink     },
	{ "flexBasis",      lsetFlexBasis      },
	{ "flexDirection",  lsetFlexDirection  },
	{ "flexWrap",       lsetFlexWrap       },
	{ "justifyContent", lsetJustifyContent },
	{ "alignItems",     lsetAlignItems     },
	{ "alignContent",   lsetAlignContent   },
	{ "alignSelf",      lsetAlignSelf      },
	{ "margin",         lsetMargin         },
	{ "marginTop",      lsetMarginTop      },
	{ "marginBottom",   lsetMarginBottom   },
	{ "marginLeft",     lsetMarginLeft     },
	{ "marginRight",    lsetMarginRight    },
	{ "marginX",        lsetMarginX        },
	{ "marginY",        lsetMarginY        },
	{ "padding",        lsetPadding        },
	{ "paddingTop",     lsetPaddingTop     },
	{ "paddingBottom",  lsetPaddingBottom  },
	{ "paddingLeft",    lsetPaddingLeft    },
	{ "paddingRight",   lsetPaddingRight   },
	{ "paddingX",       lsetPaddingX       },
	{ "paddingY",       lsetPaddingY       },
	{ "borderTop",      lsetBorderTop      },
	{ "borderBottom",   lsetBorderBottom   },
	{ "borderLeft",     lsetBorderLeft     },
	{ "borderRight",    lsetBorderRight    },
	{ "gap",            lsetGap            },
	{ "rowGap",         lsetRowGap         },
	{ "columnGap",      lsetColumnGap      },
	{ "overflow",       lsetOverflow       },
	{ "boxSizing",      lsetBoxSizing      },
	{ "display",        lsetDisplay        },
	{ "position",       lsetPosition       },
	{ "top",            lsetTop            },
	{ "bottom",         lsetBottom         },
	{ "left",           lsetLeft           },
	{ "right",          lsetRight          },
};
#define N_BOX_SETTERS (int)(sizeof(box_setter_list)/sizeof(box_setter_list[0]))

// yoga.node_set_box_props(node, props)
// Single-pass: directly lua_getfield each key from props, no intermediate table.
// Requires upvalue 2 = enum table (same convention as lnodeSet).
static int
lnodeSetBoxProps(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);

	// borderStyle → set 1px border on all edges for layout reservation
	if (lua_getfield(L, 2, "borderStyle") != LUA_TNIL)
		YGNodeStyleSetBorder(node, YGEdgeAll, 1.0f);
	lua_pop(L, 1);

	for (int i = 0; i < N_BOX_SETTERS; i++) {
		int vtype = lua_getfield(L, 2, box_setter_list[i].key);
		if (vtype == LUA_TTABLE) {
			int tbl = lua_gettop(L);
			if (coerce_or_expand_table(L, tbl, node, box_setter_list[i].key)) {
				// Named-key table was expanded into individual edge calls.
				lua_pop(L, 1);
				continue;
			}
			vtype = LUA_TSTRING;
		}
		if (vtype != LUA_TNIL)
			box_setter_list[i].fn(L, node);
		lua_pop(L, 1);
	}

	// overflowX/Y fallback (Yoga has no per-axis overflow); Y wins if both set
	if (lua_getfield(L, 2, "overflowX") != LUA_TNIL) lsetOverflow(L, node);
	lua_pop(L, 1);
	if (lua_getfield(L, 2, "overflowY") != LUA_TNIL) lsetOverflow(L, node);
	lua_pop(L, 1);

	return 0;
}

// yoga.node_set_text_props(node, props, iw, ih)
// Sets width/height (with integer defaults iw/ih) plus optional flex/margin/overflow.
// Requires upvalue 2 = enum table (alignSelf and overflow use getEnum).
static int
lnodeSetTextProps(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	int iw = (int)luaL_checkinteger(L, 3);
	int ih = (int)luaL_checkinteger(L, 4);

	if (lua_getfield(L, 2, "width") != LUA_TNIL) {
		lsetWidth(L, node);
	} else {
		lua_pop(L, 1);
		lua_pushinteger(L, iw);
		lsetWidth(L, node);
	}
	lua_pop(L, 1);

	if (lua_getfield(L, 2, "height") != LUA_TNIL) {
		lsetHeight(L, node);
	} else {
		lua_pop(L, 1);
		lua_pushinteger(L, ih);
		lsetHeight(L, node);
	}
	lua_pop(L, 1);

	static const struct { const char *key; setfunc fn; } text_opt[] = {
		{ "flexGrow",     lsetFlexGrow     },
		{ "flexShrink",   lsetFlexShrink   },
		{ "flexBasis",    lsetFlexBasis    },
		{ "alignSelf",    lsetAlignSelf    },
		{ "overflow",     lsetOverflow     },
		{ "marginTop",    lsetMarginTop    },
		{ "marginBottom", lsetMarginBottom },
		{ "marginLeft",   lsetMarginLeft   },
		{ "marginRight",  lsetMarginRight  },
	};
	for (int i = 0; i < (int)(sizeof(text_opt)/sizeof(text_opt[0])); i++) {
		if (lua_getfield(L, 2, text_opt[i].key) != LUA_TNIL)
			text_opt[i].fn(L, node);
		lua_pop(L, 1);
	}
	return 0;
}

// --- Structural tree APIs (no upvalues needed) ---

// yoga.node_child_count(node) -> int
static int
lnodeChildCount(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	lua_pushinteger(L, (int)YGNodeGetChildCount(node));
	return 1;
}

// yoga.node_get_child(node, i) -> lightuserdata  (0-based index)
static int
lnodeGetChild(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	int i = (int)luaL_checkinteger(L, 2);
	lua_pushlightuserdata(L, YGNodeGetChild(node, (size_t)i));
	return 1;
}

// yoga.node_remove_all_children(node)
static int
lnodeRemoveAllChildren(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	YGNodeRemoveAllChildren(node);
	return 0;
}

// yoga.node_insert_child(parent, child, i)  (0-based index)
static int
lnodeInsertChild(lua_State *L) {
	YGNodeRef parent = lua_touserdata(L, 1);
	YGNodeRef child  = lua_touserdata(L, 2);
	int i = (int)luaL_checkinteger(L, 3);
	YGNodeInsertChild(parent, child, (size_t)i);
	return 0;
}

// yoga.node_reset(node) — reset style to defaults; node must have no parent/children
static int
lnodeReset(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	YGNodeReset(node);
	return 0;
}

// yoga.node_has_new_layout(node) -> bool
static int
lnodeHasNewLayout(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	lua_pushboolean(L, YGNodeGetHasNewLayout(node));
	return 1;
}

// yoga.node_set_has_new_layout(node, bool)
static int
lnodeSetHasNewLayout(lua_State *L) {
	YGNodeRef node = lua_touserdata(L, 1);
	YGNodeSetHasNewLayout(node, lua_toboolean(L, 2));
	return 0;
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

int
tui_open_yoga(lua_State *L) {
	luaL_Reg l[] = {
		{ "node_new",                lnodeNew                },
		{ "node_free",               lnodeFree               },
		{ "node_calc",               lnodeCalc               },
		{ "node_get",                lnodeGet                },
		{ "node_child_count",        lnodeChildCount         },
		{ "node_get_child",          lnodeGetChild           },
		{ "node_remove_all_children",lnodeRemoveAllChildren  },
		{ "node_insert_child",       lnodeInsertChild        },
		{ "node_reset",              lnodeReset              },
		{ "node_has_new_layout",     lnodeHasNewLayout       },
		{ "node_set_has_new_layout", lnodeSetHasNewLayout    },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	int lib_idx = lua_gettop(L);

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
	lua_createtable(L, 0, n);
	for (i=0;i<n;i++) {
		lua_pushlightuserdata(L, (void *)setter[i].func);
		lua_setfield(L, -2, setter[i].name);
	}
	int setter_idx = lua_gettop(L);

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
	lua_createtable(L, 0, n);
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
	int enum_idx = lua_gettop(L);

	// Register the three closures that need the enum table as upvalue 2.
	// Upvalue 1 = setter dispatch table (only lnodeSet uses it).
	// Upvalue 2 = enum table (lnodeSet, lnodeSetBoxProps, lnodeSetTextProps).
	lua_pushvalue(L, setter_idx); lua_pushvalue(L, enum_idx);
	lua_pushcclosure(L, lnodeSet, 2);
	lua_setfield(L, lib_idx, "node_set");

	lua_pushvalue(L, setter_idx); lua_pushvalue(L, enum_idx);
	lua_pushcclosure(L, lnodeSetBoxProps, 2);
	lua_setfield(L, lib_idx, "node_set_box_props");

	lua_pushvalue(L, setter_idx); lua_pushvalue(L, enum_idx);
	lua_pushcclosure(L, lnodeSetTextProps, 2);
	lua_setfield(L, lib_idx, "node_set_text_props");

	// Discard setter and enum tables; closures hold references via upvalues.
	lua_settop(L, lib_idx);

	// Set PointScaleFactor=1 on default config so all Yoga nodes produce
	// integer coordinates (TUI is cell-based; fractional positions like
	// \27[73.0;3.0H are rejected by terminals).
	YGConfigRef cfg = (YGConfigRef)YGConfigGetDefault();
	YGConfigSetPointScaleFactor(cfg, 1.0f);

	return 1;
}
