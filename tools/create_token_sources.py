"""Original placeholder artwork. Runtime uses baked transparent PNGs, not SVGs."""
from pathlib import Path

DEST = Path(__file__).resolve().parents[1] / "assets" / "token_sources"
DEST.mkdir(parents=True, exist_ok=True)
HEAD = '''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="384" viewBox="0 0 256 384">
<defs><linearGradient id="cloth" x2="1" y2="1"><stop stop-color="{light}"/><stop offset="1" stop-color="{dark}"/></linearGradient></defs>
<g stroke="#292c34" stroke-width="5" stroke-linejoin="round" stroke-linecap="round">'''
FOOT = '</g></svg>'
BOOTS = '<path d="M95 284L89 347 67 360Q65 368 80 368H115L122 289M134 287L141 368H180Q188 358 163 349L159 282" fill="#453a3b"/>'
SOURCES = {
    "warrior": ("#cc9359", "#6c4443", BOOTS + '''
<path d="M77 140Q128 112 179 142L190 313 66 313Z" fill="url(#cloth)"/>
<path d="M89 139L80 245 108 281H155L178 244 166 138Z" fill="#a9bcc1"/>
<path d="M124 148L124 251M92 180L158 180M91 222L165 222" stroke="#566974"/>
<path d="M75 144L53 163 62 195 94 177M165 143L196 158 189 194 159 177" fill="#c5d1ce"/>
<path d="M92 84Q94 47 128 46 164 47 166 87L159 124 100 124Z" fill="#bac9c7"/>
<path d="M100 86H158L151 104H104Z" fill="#303b45"/><path d="M129 52V117" stroke="#e9c57c"/>
<path d="M128 47Q127 20 153 16L163 49" fill="#b75f54"/>
<path d="M40 199L94 187 106 258Q88 289 62 302 35 270 40 199Z" fill="#6c8c8d"/>
<path d="M72 209V265M53 233H91" stroke="#e5c785" stroke-width="9"/>
<path d="M201 215L200 92 212 72 224 93 215 216Z" fill="#d9ded0"/>
<path d="M188 220H228M207 223V258" stroke="#d2ad65" stroke-width="9"/>
<path d="M171 183L190 239 204 236" fill="none" stroke="#9aabb1" stroke-width="15"/>
<path d="M89 265H165V284H89Z" fill="#51423a"/><rect x="119" y="264" width="21" height="21" fill="#e6be70"/>'''),
    "mage": ("#8b96cb", "#51446f", BOOTS + '''
<path d="M87 146L66 333Q131 363 187 332L166 146Z" fill="url(#cloth)"/>
<path d="M124 153L111 329M142 161L153 337" stroke="#c6b584"/>
<path d="M92 157L46 223 74 242 111 193M164 155L190 219 211 204" fill="url(#cloth)"/>
<path d="M106 91Q129 77 154 95L151 135Q132 153 109 134Z" fill="#d7b394"/>
<path d="M108 127L131 173 155 125" fill="#d8dad2"/>
<path d="M72 97L111 23 132 38 155 23 175 99Z" fill="url(#cloth)"/>
<path d="M60 102Q126 78 188 103L183 118H65Z" fill="#807cae"/>
<path d="M128 58L133 72 146 75 135 83 135 96 124 88 111 93 115 80 106 70 120 70Z" fill="#e9c785" stroke-width="3"/>
<path d="M210 350L213 88" stroke="#876548" stroke-width="13"/>
<path d="M212 91L193 67 207 32 229 58Z" fill="#7ad3d2"/>
<path d="M206 44L212 74 222 58" fill="none" stroke="#d2f0e0" stroke-width="3"/>
<path d="M82 235L99 266 76 281 57 252Z" fill="#a1754b"/>
<path d="M97 278H167V295H97Z" fill="#4c3a47"/><circle cx="130" cy="286" r="11" fill="#e9c785"/>'''),
    "rogue": ("#609f9b", "#30494c", BOOTS + '''
<path d="M84 129Q128 105 171 132L181 309 144 291 123 321 100 294 64 315Z" fill="url(#cloth)"/>
<path d="M93 166L77 261 121 285 170 262 158 165Z" fill="#4f5557"/>
<path d="M86 94Q83 41 126 38 171 39 172 93L159 143 97 143Z" fill="url(#cloth)"/>
<path d="M101 95Q129 80 156 95L149 119H109Z" fill="#292f37"/>
<path d="M111 99H119M138 99H146" stroke="#bfe6cb" stroke-width="4"/>
<path d="M100 132L159 135 151 161 110 155Z" fill="#7eb6a9"/>
<path d="M94 165L159 252" stroke="#b19b71" stroke-width="15"/>
<path d="M87 262H167V282H87Z" fill="#a2815a"/><rect x="118" y="260" width="24" height="26" fill="#dac28b"/>
<path d="M79 178L52 233 67 248M170 176L188 225 203 214" fill="none" stroke="#547976" stroke-width="24"/>
<path d="M51 242L37 297 49 285 69 246M195 217L211 160 221 153 213 218" fill="#c5d5d4"/>
<path d="M42 242L72 249M191 223L221 215" stroke="#cba776" stroke-width="7"/>
<path d="M145 287L157 312 171 306 165 282Z" fill="#836244"/>'''),
    "cleric": ("#cb8094", "#724b6c", BOOTS + '''
<path d="M88 138L69 331Q129 357 189 331L167 139Z" fill="url(#cloth)"/>
<path d="M104 145L105 327 126 342 152 327 149 145" fill="#e4c8aa"/>
<path d="M117 198V245M99 215H136" stroke="#bd9554" stroke-width="9"/>
<path d="M96 85Q96 53 128 53 161 52 161 88L154 124 108 123Z" fill="#d6ab92"/>
<path d="M95 92L93 65 107 36 128 27 149 38 166 70 164 94 145 70 113 70Z" fill="#bfcbd0"/>
<path d="M127 36V64M116 48H138" stroke="#e6c27c" stroke-width="6"/>
<path d="M87 138L56 155 60 190 101 167M166 139L193 155 188 193 154 168" fill="#b8b6c0"/>
<path d="M71 191L61 230 79 249M177 186L193 236" fill="none" stroke="#c5bbc2" stroke-width="24"/>
<path d="M198 343V166" stroke="#92734f" stroke-width="12"/>
<path d="M185 154L177 126 192 114 207 114 220 130 212 154Z" fill="#cbd4cf"/>
<path d="M190 124V145M204 124V145" stroke="#9baeb5"/>
<path d="M68 227L97 240 91 287 57 272Z" fill="#694a57"/>
<path d="M81 244L75 269M65 253L90 260" stroke="#e1bd72" stroke-width="4"/>'''),
    "skeleton": ("#988879", "#514746", '''
<path d="M106 255L97 305 87 350M147 255L157 305 169 349" fill="none" stroke="#292c34" stroke-width="20"/>
<path d="M106 255L97 305 87 350M147 255L157 305 169 349" fill="none" stroke="#d9cfaf" stroke-width="11"/>
<path d="M85 349L65 363H103M167 349L188 363H152" fill="none" stroke="#d9cfaf" stroke-width="10"/>
<path d="M82 131L61 252 99 238 125 278 155 239 191 257 174 133Z" fill="url(#cloth)"/>
<path d="M129 125V246M99 149Q128 168 157 149M97 176Q127 193 159 176M101 204Q127 221 155 204" fill="none" stroke="#d9cfaf" stroke-width="10"/>
<path d="M101 240L126 255 155 239" fill="none" stroke="#d9cfaf" stroke-width="12"/>
<path d="M94 65Q99 32 128 32 162 34 165 65L160 105 145 113V130H109V113L95 103Z" fill="#e4d9b8"/>
<path d="M104 76L119 71 119 91 105 91M138 72L154 77 151 92H138" fill="#30323b"/>
<path d="M127 92L121 105H135Z" fill="#30323b"/><path d="M117 115V125M128 115V125M138 115V125" stroke-width="3"/>
<path d="M84 147L48 195 68 228M171 148L192 194 218 172" fill="none" stroke="#d9cfaf" stroke-width="12"/>
<path d="M34 212L88 222 76 285 25 272Z" fill="#b89b71"/><path d="M41 231L73 236M39 245L68 250M36 259L60 263" stroke="#675849" stroke-width="3"/>
<path d="M218 177V72" stroke="#9a7451" stroke-width="10"/>
<path d="M208 76L201 48 218 40 235 48 227 76Z" fill="#a9b9b9"/>
<path d="M201 47H235" stroke="#d4c195" stroke-width="7"/>'''),
}
for key, (light, dark, body) in SOURCES.items():
    (DEST / f"{key}.svg").write_text(HEAD.format(light=light, dark=dark) + body + FOOT)
print(f"Wrote {len(SOURCES)} original SVG sources to {DEST}")
