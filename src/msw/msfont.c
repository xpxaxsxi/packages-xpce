/*  $Id$

    Part of XPCE
    Designed and implemented by Anjo Anjewierden and Jan Wielemaker
    E-mail: jan@swi.psy.uva.nl

    Copyright (C) 1994 University of Amsterdam. All rights reserved.
*/

#include "include.h"

#define FONTTABLESIZE	256
#define STOCKFMT "GetStockObject(%d)"

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
We should consider parsing the x_name value as a description of an
MS-Windows LOGFONT structure.  Something like this:

height(16):italic:weight(700):face(blabla) 
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

typedef struct _lname
{ char *name;
  int   value;
} lname;


static lname charset_names[] = 
{ { "ansi",	ANSI_CHARSET },
  { "oem",	OEM_CHARSET },
  { "symbol",	SYMBOL_CHARSET },
#ifdef UNICODE_CHARSET
  { "unicode",	UNICODE_CHARSET },
#endif
  { NULL,	0 }
};


static lname outprecision_names[] = 
{ { "character",OUT_CHARACTER_PRECIS },
  { "default",	OUT_DEFAULT_PRECIS },
  { "string",	OUT_STRING_PRECIS },
  { "stroke",	OUT_STROKE_PRECIS },
  { NULL,	0 }
};


static lname clipprecision_names[] = 
{ { "character",CLIP_CHARACTER_PRECIS },
  { "default",	CLIP_DEFAULT_PRECIS },
  { "stroke",	CLIP_STROKE_PRECIS },
  { NULL,	0 }
};


static lname quality_names[] = 
{ { "default",  DEFAULT_QUALITY },
  { "draft",	DRAFT_QUALITY },
  { "proof",	PROOF_QUALITY },
  { NULL,	0 }
};


static lname pitch_names[] = 
{ { "default",  DEFAULT_PITCH },
  { "fixed",	FIXED_PITCH },
  { "variable",	VARIABLE_PITCH },
  { NULL,	0 }
};


static lname family_names[] = 
{ { "decorative",  FF_DECORATIVE },
  { "dontcare",	   FF_DONTCARE },
  { "modern",	   FF_MODERN },
  { "roman",	   FF_ROMAN },
  { "script",	   FF_SCRIPT },
  { "swiss",	   FF_SWISS },
  { NULL,	0 }
};


static int
named_attribute(char *s, lname *names, int mask, BYTE *value)
{ char *sc = s;

  if ( *sc++ != '(' )
    return -1;

  for(; names; names++)
  { char *q = sc;
    char *r = names->name;

    while(*r && tolower(*q) == tolower(*r))
      r++, q++;
    if ( *r == EOS && *q++ == ')' )
    { *value &= ~mask;
      *value |= names->value;
      return q-s;
    }
  }

  return -1;
}


static int
string_attribute(char *s, char *string, int len)
{ char *q = s;
  char *r = string;
  
  if ( *q++ != '(' )
    return -1;
  while(isletter(*q) && len-- > 0)
    *r++ = *q++;
  if ( *q++ == ')' )
  { *r = EOS;
    return q-s;
  }

  return -1;
}


static status
long_attribute(char *s, LONG *val)
{ char *q = s;
  LONG rval = 0;

  if ( *q++ != '(' )
    return -1;
  while(isdigit(*q))
    rval = rval * 10 + *q++ - '0';
  if ( *q++ == ')' )
  { *val = rval;
    return q-s;
  }

  return -1;
}


static status
bool_attribute(char *s, BYTE *val)
{ *val = TRUE;

  return 0;
} 


static status
parse_font(char *s, LOGFONT *lfont)
{ while(*s)
  { char att[100];
    int n;
    char *q;

    for(q=att; isletter(*s); *q++ = *s++)
      ;
    *q = EOS;

    if ( stricmp(att, "height") == 0 )
      n=long_attribute(s, &lfont->lfHeight);
    else if ( stricmp(att, "width") == 0 )
      n=long_attribute(s, &lfont->lfWidth);
    else if ( stricmp(att, "escapement") == 0 )
      n=long_attribute(s, &lfont->lfEscapement);
    else if ( stricmp(att, "orientation") == 0 )
      n=long_attribute(s, &lfont->lfOrientation);
    else if ( stricmp(att, "weight") == 0 )
      n=long_attribute(s, &lfont->lfWeight);
    else if ( stricmp(att, "italic") == 0 )
      n=bool_attribute(s, &lfont->lfItalic);
    else if ( stricmp(att, "underline") == 0 )
      n=bool_attribute(s, &lfont->lfUnderline);
    else if ( stricmp(att, "strikeout") == 0 )
      n=bool_attribute(s, &lfont->lfStrikeOut);
    else if ( stricmp(att, "charset") == 0 )
      n=named_attribute(s, charset_names, 0xff, &lfont->lfCharSet);
    else if ( stricmp(att, "outprecision") == 0 )
      n=named_attribute(s, outprecision_names, 0xff, &lfont->lfOutPrecision);
    else if ( stricmp(att, "clipprecision") == 0 )
      n=named_attribute(s, clipprecision_names, 0xff, &lfont->lfClipPrecision);
    else if ( stricmp(att, "quality") == 0 )
      n=named_attribute(s, quality_names, 0xff, &lfont->lfQuality);
    else if ( stricmp(att, "pitch") == 0 )
      n=named_attribute(s, pitch_names, 0x3, &lfont->lfPitchAndFamily);
    else if ( stricmp(att, "family") == 0 )
      n=named_attribute(s, family_names, 0xf8, &lfont->lfPitchAndFamily);
    else if ( stricmp(att, "face") == 0 )
      n=string_attribute(s, lfont->lfFaceName, LF_FACESIZE);
    else
      Cprintf("Bad font-attribute name: %s\n", att);
  
    if ( n < 0 )
    { Cprintf("Bad value for font-attribute %s\n", att);
      while( *s && *s != ':' )
	s++;
    } else
    { DEBUG(NAME_font, Cprintf("att %s: read %d chars\n", att, n));
      s += n;
      if ( *s == ':' )
	s++;
    }
  }

  succeed;
}


status
ws_create_font(FontObj f, DisplayObj d)
{ WsFont wsf = alloc(sizeof(ws_font));
#ifdef __WIN32__
  int widths[FONTTABLESIZE];
#else
  short widths[FONTTABLESIZE];
#endif
  HDC hdc;
  HFONT old;
  int n;
  TEXTMETRIC tm;
  int stock;

  if ( sscanf(strName(f->x_name), STOCKFMT, &stock) == 1 )
  { wsf->hfont      = GetStockObject(stock);
    wsf->from_stock = TRUE;
  } else
  { LOGFONT lfont;
    Real  scale  = getResourceValueObject(f, NAME_scale);
    float fscale = (scale ? valReal(scale) : 1.4);

    memset(&lfont, 0, sizeof(lfont));
    lfont.lfHeight          = (int)((float) valInt(f->points) * fscale);
    lfont.lfWeight          = (f->style == NAME_bold ? FW_BOLD : FW_NORMAL);
    lfont.lfItalic          = ((f->style == NAME_italic ||
				f->style == NAME_oblique) ? 1 : 0);
    lfont.lfPitchAndFamily  = (f->family == NAME_screen  ? FIXED_PITCH
							 : DEFAULT_PITCH);
    lfont.lfPitchAndFamily |= (f->family == NAME_helvetica ? FF_SWISS :
			       f->family == NAME_times     ? FF_ROMAN :
			       f->family == NAME_screen    ? FF_MODERN :
							     FF_DONTCARE);
  
    if ( instanceOfObject(f->x_name, ClassCharArray) )
    { strcpy(lfont.lfFaceName, strName(f->family));

      parse_font(strName(f->x_name), &lfont);
    }

    if ( !(wsf->hfont = CreateFontIndirect(&lfont)) )
    { Cprintf("Failed to create logical font; replacing with stock font\n");

      if ( f->family == NAME_screen )
      { if ( f->style == NAME_bold )
	  stock = SYSTEM_FIXED_FONT;
	else
	  stock = ANSI_FIXED_FONT;
      } else
      { if ( f->style == NAME_bold )
	  stock = SYSTEM_FONT;
	else
	  stock = ANSI_VAR_FONT;
      }

      wsf->hfont      = GetStockObject(stock);
      wsf->from_stock = TRUE;
    } else
      wsf->from_stock = FALSE;
  }

  wsf->widths     = alloc(FONTTABLESIZE * sizeof(cwidth));
  assign(f, b16, OFF);

  hdc = GetDC(NULL);
  old = SelectObject(hdc, wsf->hfont);
  GetCharWidth(hdc, 0, FONTTABLESIZE-1, widths);
  for(n=0; n<FONTTABLESIZE; n++)
    wsf->widths[n] = widths[n];
  GetTextMetrics(hdc, &tm);
  wsf->ascent = tm.tmAscent + tm.tmExternalLeading;
  wsf->descent = tm.tmDescent;
  SelectObject(hdc, old);
  ReleaseDC(NULL, hdc);

  if ( wsf->widths['i'] == wsf->widths['w'] )
    assign(f, fixed_width, ON);
  else
    assign(f, fixed_width, OFF);

  registerXrefObject(f, d, wsf);

  succeed;
}


void
ws_destroy_font(FontObj f, DisplayObj d)
{ WsFont wsf = (WsFont) getExistingXrefObject(f, d);

  DEBUG(NAME_font, Cprintf("ws_destroy_font(%s)\n", pp(f)));

  if ( wsf )
  { if ( !wsf->from_stock )
      ZDeleteObject(wsf->hfont);
    unregisterXrefObject(f, d);
  }
}


static struct system_font
{ char *name;
  int  id;
} window_fonts [] = 
{ { "ansi_fixed",	ANSI_FIXED_FONT },
  { "ansi_var",		ANSI_VAR_FONT },
  { "device_default",	DEVICE_DEFAULT_FONT },
  { "oem_fixed",	OEM_FIXED_FONT },
  { "system",		SYSTEM_FONT },
  { "system_fixed",	SYSTEM_FIXED_FONT },

  { NULL,		0 }
};


status
ws_system_fonts(DisplayObj d)
{ struct system_font *sf;

  for(sf = window_fonts; sf->name; sf++)
  { char buf[256];

    sprintf(buf, STOCKFMT, sf->id);

    newObject(ClassFont,
	      NAME_win, CtoKeyword(sf->name), DEFAULT,
	      CtoName(buf), 0);
  }

  succeed;
}
