--------------------------------------------------------------------------
--script for auto_funcs.h and auto_funcs.cpp generation
--expects LuaJIT
--------------------------------------------------------------------------
assert(_VERSION=='Lua 5.1',"Must use LuaJIT")
assert(bit,"Must use LuaJIT")
local script_args = {...}
local COMPILER = script_args[1]
local INTERNAL_GENERATION = script_args[2]=="true" 
local CPRE,CTEST
if COMPILER == "gcc" or COMPILER == "clang" then
    CPRE = COMPILER..[[ -E -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_API="" -DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER.." --version"
elseif COMPILER == "cl" then
    CPRE = COMPILER..[[ /E /DIMGUI_DISABLE_OBSOLETE_FUNCTIONS /DIMGUI_API="" /DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER
else
    print("Working without compiler ")
	error("cant work with "..COMPILER.." compiler")
end
--test compiler present
local HAVE_COMPILER = false

local pipe,err = io.popen(CTEST,"r")
if pipe then
    local str = pipe:read"*a"
    print(str)
    pipe:close()
    if str=="" then
        HAVE_COMPILER = false
    else
        HAVE_COMPILER = true
    end
else
    HAVE_COMPILER = false
    print(err)
end
assert(HAVE_COMPILER,"gcc, clang or cl needed to run script")


print("HAVE_COMPILER",HAVE_COMPILER)
print("INTERNAL_GENERATION",INTERNAL_GENERATION)
--get implementations
local implementations = {}
for i=3,#script_args do table.insert(implementations,script_args[i]) end

--------------------------------------------------------------------------
--this table has the functions to be skipped in generation
--------------------------------------------------------------------------
local cimgui_manuals = {
    igLogText = true,
    ImGuiTextBuffer_appendf = true,
    igColorConvertRGBtoHSV = true,
    igColorConvertHSVtoRGB = true
}
--------------------------------------------------------------------------
--this table is a dictionary to force a naming of function overloading (instead of algorythmic generated)
--first level is cimguiname without postfix, second level is the signature of the function, value is the
--desired name
---------------------------------------------------------------------------
local cimgui_overloads = {
    --igPushID = {
        --["(const char*)"] =           "igPushIDStr",
        --["(const char*,const char*)"] = "igPushIDRange",
        --["(const void*)"] =           "igPushIDPtr",
        --["(int)"] =                   "igPushIDInt"
    --},
}

--------------------------header definitions
local cimgui_header = 
[[//This file is automatically generated by generator.lua from https://github.com/cimgui/cimgui
//based on imgui.h file version XXX from Dear ImGui https://github.com/ocornut/imgui
]]
local gdefines = {} --for FLT_MAX and others
--------------------------------------------------------------------------
--helper functions
--------------------------------functions for C generation
--load parser module
local cpp2ffi = require"cpp2ffi"
local read_data = cpp2ffi.read_data
local save_data = cpp2ffi.save_data
local copyfile = cpp2ffi.copyfile
local serializeTableF = cpp2ffi.serializeTableF

local function func_header_impl_generate(FP)

    local outtab = {}
    
    for _,t in ipairs(FP.funcdefs) do
        if t.cimguiname then
            local cimf = FP.defsT[t.cimguiname]
            local def = cimf[t.signature]
			local addcoment = def.comment or ""
			if def.constructor then
				-- it happens with vulkan impl but constructor ImGui_ImplVulkanH_Window is not needed
			    --assert(def.stname ~= "","constructor without struct")
                --table.insert(outtab,"CIMGUI_API "..def.stname.."* "..def.ov_cimguiname ..(empty and "(void)" or --def.args)..";"..addcoment.."\n")
            elseif def.destructor then
                --table.insert(outtab,"CIMGUI_API void "..def.ov_cimguiname..def.args..";"..addcoment.."\n")
			else
                
                if def.stname == "" then --ImGui namespace or top level
                    table.insert(outtab,"CIMGUI_API".." "..def.ret.." "..def.ov_cimguiname..def.args..";"..addcoment.."\n")
                else
					cpp2ffi.prtable(def)
                    error("class function in implementations")
                end
            end
        else --not cimguiname
            table.insert(outtab,t.comment:gsub("%%","%%%%").."\n")-- %% substitution for gsub
        end
    end
    local cfuncsstr = table.concat(outtab)
    cfuncsstr = cfuncsstr:gsub("\n+","\n") --several empty lines to one empty line
    return cfuncsstr
end
local function func_header_generate(FP)

    local outtab = {}
    table.insert(outtab,"#ifndef CIMGUI_DEFINE_ENUMS_AND_STRUCTS\n")
    for k,v in pairs(FP.embeded_structs) do
        table.insert(outtab,"typedef "..v.." "..k..";\n")
    end

    for ttype,v in pairs(FP.templates) do
		for ttypein,_ in pairs(v) do
			local te = ttypein:gsub("%s","_")
			te = te:gsub("%*","Ptr")
        table.insert(outtab,"typedef "..ttype.."<"..ttypein.."> "..ttype.."_"..te..";\n")
		end
    end

    table.insert(outtab,"#endif //CIMGUI_DEFINE_ENUMS_AND_STRUCTS\n")
    for _,t in ipairs(FP.funcdefs) do

        if t.cimguiname then
        local cimf = FP.defsT[t.cimguiname]
        local def = cimf[t.signature]
        assert(def,t.signature..t.cimguiname)
        local manual = FP.get_manuals(def)
        if not manual and not def.templated then

            local addcoment = def.comment or ""
            local empty = def.args:match("^%(%)") --no args
            if def.constructor then
                assert(def.stname ~= "","constructor without struct")
                table.insert(outtab,"CIMGUI_API "..def.stname.."* "..def.ov_cimguiname ..(empty and "(void)" or def.args)..";"..addcoment.."\n")
            elseif def.destructor then
                table.insert(outtab,"CIMGUI_API void "..def.ov_cimguiname..def.args..";"..addcoment.."\n")
            else --not constructor

                if def.stname == "" then --ImGui namespace or top level
                    table.insert(outtab,"CIMGUI_API "..def.ret.." ".. def.ov_cimguiname ..(empty and "(void)" or def.args)..";"..addcoment.."\n")
                else
                    table.insert(outtab,"CIMGUI_API "..def.ret.." "..def.ov_cimguiname..def.args..";"..addcoment.."\n")
                end
            end 
        end
        else --not cimguiname
            table.insert(outtab,t.comment:gsub("%%","%%%%").."\n")-- %% substitution for gsub
        end
    end

    local cfuncsstr = table.concat(outtab)
    cfuncsstr = cfuncsstr:gsub("\n+","\n") --several empty lines to one empty line
    return cfuncsstr
end


local function ImGui_f_implementation(outtab,def)
    local ptret = def.retref and "&" or ""
    table.insert(outtab,"CIMGUI_API".." "..def.ret.." "..def.ov_cimguiname..def.args.."\n")
    table.insert(outtab,"{\n")
	local namespace = def.namespace and def.namespace.."::" or ""
    if def.isvararg then
        local call_args = def.call_args:gsub("%.%.%.","args")
        table.insert(outtab,"    va_list args;\n")
        table.insert(outtab,"    va_start(args, fmt);\n")
        if def.ret~="void" then
            table.insert(outtab,"    "..def.ret.." ret = "..namespace..def.funcname.."V"..call_args..";\n")
        else
            table.insert(outtab,"    "..namespace..def.funcname.."V"..call_args..";\n")
        end
        table.insert(outtab,"    va_end(args);\n")
        if def.ret~="void" then
            table.insert(outtab,"    return ret;\n")
        end
    elseif def.nonUDT then
        if def.nonUDT == 1 then
            table.insert(outtab,"    *pOut = "..namespace..def.funcname..def.call_args..";\n")
        end
    else --standard ImGui
        table.insert(outtab,"    return "..ptret..namespace..def.funcname..def.call_args..";\n")
    end
    table.insert(outtab,"}\n")
end
local function struct_f_implementation(outtab,def)
    local empty = def.args:match("^%(%)") --no args
    local ptret = def.retref and "&" or ""

    local imgui_stname = def.stname

    table.insert(outtab,"CIMGUI_API".." "..def.ret.." "..def.ov_cimguiname..def.args.."\n")
    table.insert(outtab,"{\n")
    if def.isvararg then
        local call_args = def.call_args:gsub("%.%.%.","args")
        table.insert(outtab,"    va_list args;\n")
        table.insert(outtab,"    va_start(args, fmt);\n")
        if def.ret~="void" then
            table.insert(outtab,"    "..def.ret.." ret = self->"..def.funcname.."V"..call_args..";\n")
        else
            table.insert(outtab,"    self->"..def.funcname.."V"..call_args..";\n")
        end
        table.insert(outtab,"    va_end(args);\n")
        if def.ret~="void" then
            table.insert(outtab,"    return ret;\n")
        end
    elseif def.nonUDT then
        if def.nonUDT == 1 then
            table.insert(outtab,"    *pOut = self->"..def.funcname..def.call_args..";\n")
        end
    else --standard struct
        table.insert(outtab,"    return "..ptret.."self->"..def.funcname..def.call_args..";\n")
    end
    table.insert(outtab,"}\n")
end
local function func_implementation(FP)

    local outtab = {}
    for _,t in ipairs(FP.funcdefs) do
        repeat -- continue simulation
        if not t.cimguiname then break end
        local cimf = FP.defsT[t.cimguiname]
        local def = cimf[t.signature]
        assert(def)
        local manual = FP.get_manuals(def)
        if not manual and not def.templated then 
            if def.constructor then
                assert(def.stname ~= "","constructor without struct")
                local empty = def.args:match("^%(%)") --no args
                table.insert(outtab,"CIMGUI_API "..def.stname.."* "..def.ov_cimguiname..(empty and "(void)" or def.args).."\n")
                table.insert(outtab,"{\n")
                table.insert(outtab,"    return IM_NEW("..def.stname..")"..def.call_args..";\n")
                table.insert(outtab,"}\n")
            elseif def.destructor then
                local args = "("..def.stname.."* self)"
                local fname = def.stname.."_destroy" 
                table.insert(outtab,"CIMGUI_API void "..fname..args.."\n")
                table.insert(outtab,"{\n")
                table.insert(outtab,"    IM_DELETE(self);\n")
                table.insert(outtab,"}\n")
            elseif def.stname == "" then
                ImGui_f_implementation(outtab,def)
            else -- stname
                struct_f_implementation(outtab,def)
            end
        end
        until true
    end
    return table.concat(outtab)
end
-------------------functions for getting and setting defines
local function get_defines(t)
    if COMPILER == "cl" then print"can't get defines with cl compiler"; return {} end
    local pipe,err = io.popen(COMPILER..[[ -E -dM -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_API="" -DIMGUI_IMPL_API="" ../imgui/imgui.h]],"r")
    local defines = {}
    while true do
        local line = pipe:read"*l"
        if not line then break end
        local key,value = line:match([[#define%s+(%S+)%s+(.+)]])
        if not key or not value then 
            --print(line)
        else
            defines[key]=value
        end
    end
    pipe:close()
    --require"anima.utils"
    --prtable(defines)
    --FLT_MAX
    local ret = {}
    for i,v in ipairs(t) do
        local aa = defines[v]
        while true do
            local tmp = defines[aa]
            if not tmp then 
                break
            else
                aa = tmp
            end
        end
        ret[v] = aa
    end
    return ret
end
  --subtitution of FLT_MAX value for FLT_MAX 
local function set_defines(fdefs)
    for k,defT in pairs(fdefs) do
        for i,def in ipairs(defT) do
            for name,default in pairs(def.defaults) do
                if default == gdefines.FLT_MAX then
                    def.defaults[name] = "FLT_MAX"
                end
            end
        end
    end
end 
--this creates defsBystruct in case you need to list by struct container
local function DefsByStruct(FP)
    local structs = {}
    for fun,defs in pairs(FP.defsT) do
        local stname = defs[1].stname
        structs[stname] = structs[stname] or {}
        table.insert(structs[stname],defs)--fun)
    end
    FP.defsBystruct = structs
end  




----------custom ImVector templates
local function generate_templates(code,codeimpool,templates)
    table.insert(code,"\n"..[[typedef struct ImVector{int Size;int Capacity;void* Data;} ImVector;]].."\n")
    for ttype,v in pairs(templates) do
        --local te = k:gsub("%s","_")
        --te = te:gsub("%*","Ptr")
		if ttype == "ImVector" then
			for te,newte in pairs(v) do
				table.insert(code,"typedef struct ImVector_"..newte.." {int Size;int Capacity;"..te.."* Data;} ImVector_"..newte..";\n")
			end
		elseif ttype == "ImPool" then
			--declare ImGuiStorage
			for te,newte in pairs(v) do
				table.insert(codeimpool,"typedef struct ImVector_"..newte.." {int Size;int Capacity;"..te.."* Data;} ImVector_"..newte..";\n")
				table.insert(codeimpool,"typedef struct ImPool_"..newte.." {ImVector_"..te.." Buf;ImGuiStorage Map;ImPoolIdx FreeIdx;} ImPool_"..newte..";\n")
			end
		elseif ttype == "ImChunkStream" then
			for te,newte in pairs(v) do
				table.insert(code,"typedef struct ImVector_"..newte.." {int Size;int Capacity;"..te.."* Data;} ImVector_"..newte..";\n")
				table.insert(code,"typedef struct ImChunkStream_"..newte.." {ImVector_"..te.." Buf;} ImChunkStream_"..newte..";\n")
			end
		end
    end
end
--generate cimgui.cpp cimgui.h 
local function cimgui_generation(parser)

--[[
	-- clean ImVector:contains() for not applicable types
	local clean_f = {}
	for k,v in pairs(parser.defsT) do
		if k:match"ImVector" and k:match"contains" then
			--cpp2ffi.prtable(k,v)
			local stname = v[1].stname
			if not(stname:match"float" or stname:match"int" or stname:match"char") then
				parser.defsT[k] = nil
				--delete also from funcdefs
				for i,t in ipairs(parser.funcdefs) do
					if t.cimguiname == k then
						table.remove(parser.funcdefs, i)
						break
					end
				end
			end
		end
	end
--]]
	--------------------------------------------------
    local hstrfile = read_data"./cimgui_template.h"

	local outpre,outpost = parser:gen_structs_and_enums()
	parser.templates.ImVector.T = nil
	cpp2ffi.prtable(parser.templates)
	cpp2ffi.prtable(parser.typenames)
	
	local outtab = {}
	local outtabpool = {}
    generate_templates(outtab, outtabpool, parser.templates)
	
	--move outtabpool after ImGuiStorage definition
	local outpost1, outpost2 = outpost:match("^(.+struct ImGuiStorage%s*\n%b{};\n)(.+)$")
	outpost = outpost1..table.concat(outtabpool)..outpost2

	local cstructsstr = outpre..table.concat(outtab,"")..outpost --..(extra or "")

    hstrfile = hstrfile:gsub([[#include "imgui_structs%.h"]],cstructsstr)
    local cfuncsstr = func_header_generate(parser)
    hstrfile = hstrfile:gsub([[#include "auto_funcs%.h"]],cfuncsstr)
    save_data("./output/cimgui.h",cimgui_header,hstrfile)
    
    --merge it in cimgui_template.cpp to cimgui.cpp
    local cimplem = func_implementation(parser)

    local hstrfile = read_data"./cimgui_template.cpp"

    hstrfile = hstrfile:gsub([[#include "auto_funcs%.cpp"]],cimplem)
    save_data("./output/cimgui.cpp",cimgui_header,hstrfile)

end
--------------------------------------------------------
-----------------------------do it----------------------
--------------------------------------------------------
--get imgui.h version--------------------------
local pipe,err = io.open("../imgui/imgui.h","r")
if not pipe then
    error("could not open file:"..err)
end
local imgui_version
while true do
    local line = pipe:read"*l"
    imgui_version = line:match([[#define%s+IMGUI_VERSION%s+(".+")]])
    if imgui_version then break end
end
pipe:close()
cimgui_header = cimgui_header:gsub("XXX",imgui_version)
print("IMGUI_VERSION",imgui_version)
--get some defines----------------------------
gdefines = get_defines{"IMGUI_VERSION","FLT_MAX"}
                                

--funtion for parsing imgui headers
local function parseImGuiHeader(header,names)
	--prepare parser
	local parser = cpp2ffi.Parser()
	parser.getCname = function(stname,funcname)
		local pre = (stname == "") and "ig" or stname.."_"
		return pre..funcname
	end
	parser.cname_overloads = cimgui_overloads
	parser.manuals = cimgui_manuals
	parser.UDTs = {"ImVec2","ImVec4","ImColor","ImRect"}
	
	local pipe,err = io.popen(CPRE..header,"r")
	
	if not pipe then
		error("could not execute COMPILER "..err)
	end
	
	local iterator = cpp2ffi.location
	
	--[[
	local tableo = {}
	local line
	repeat 
		line =pipe:read"*l"
		table.insert(tableo,line)
	until not line
	cpp2ffi.save_data("cdefs1.lua",table.concat(tableo,"\n"))
	--]]
	for line,loca,loca2 in iterator(pipe,names,{},COMPILER) do
		parser:insert(line, loca)
		--table.insert(tableo,line)
		--print(loca,loca2)
	end
	--cpp2ffi.save_data("cdefs1.lua",table.concat(tableo))
	pipe:close()
	return parser
end
--generation
print("------------------generation with "..COMPILER.."------------------------")
local parser1
if INTERNAL_GENERATION then
	save_data("headers.h",[[#include "../imgui/imgui.h" 
	#include "../imgui/imgui_internal.h"]])
	parser1 = parseImGuiHeader([[headers.h]],{[[imgui]],[[imgui_internal]],[[imstb_textedit]]})
	os.remove("headers.h")
else
	parser1 = parseImGuiHeader([[../imgui/imgui.h]],{[[imgui]]})
end
parser1:do_parse()

save_data("./output/overloads.txt",parser1.overloadstxt)
cimgui_generation(parser1)

----------save fundefs in definitions.lua for using in bindings
--DefsByStruct(pFP)
set_defines(parser1.defsT) 
save_data("./output/definitions.lua",serializeTableF(parser1.defsT))

----------save struct and enums lua table in structs_and_enums.lua for using in bindings
local structs_and_enums_table = parser1:gen_structs_and_enums_table()
--correct Pair union member if exists (until 1.71)
if structs_and_enums_table["structs"]["Pair"] then
structs_and_enums_table["structs"]["Pair"][2]["name"] = ""
structs_and_enums_table["structs"]["Pair"][2]["type"] = structs_and_enums_table["structs"]["Pair"][2]["type"] .. "}"
end
-- union in 1.72 and after
if structs_and_enums_table["structs"]["ImGuiStoragePair"] then
structs_and_enums_table["structs"]["ImGuiStoragePair"][2]["name"] = ""
structs_and_enums_table["structs"]["ImGuiStoragePair"][2]["type"] = structs_and_enums_table["structs"]["ImGuiStoragePair"][2]["type"] .. "}"
end
-----------------------
save_data("./output/structs_and_enums.lua",serializeTableF(structs_and_enums_table))
save_data("./output/typedefs_dict.lua",serializeTableF(parser1.typedefs_dict))


--check every function has ov_cimguiname
-- for k,v in pairs(parser1.defsT) do
	-- for _,def in ipairs(v) do
		-- assert(def.ov_cimguiname)
	-- end
-- end

--=================================Now implementations

local parser2

if #implementations > 0 then
	print("------------------implementations generation with "..COMPILER.."------------------------")
    parser2 = cpp2ffi.Parser()
	
	local config = require"config_generator"
    
    for i,impl in ipairs(implementations) do
        local source = [[../imgui/examples/imgui_impl_]].. impl .. ".h "
        local locati = [[imgui_impl_]].. impl

		local define_cmd = COMPILER=="cl" and [[ /E /D]] or [[ -E -D]]
		local extra_defines = ""
		if impl == "opengl3" then extra_defines = define_cmd .. "IMGUI_IMPL_OPENGL_LOADER_GL3W " end
		local include_cmd = COMPILER=="cl" and [[ /I ]] or [[ -I ]]
		local extra_includes = include_cmd.." ../imgui "
		if config[impl] then
			for j,inc in ipairs(config[impl]) do
				extra_includes = extra_includes .. include_cmd .. inc .. " "
			end
		end

        local pipe,err = io.popen(CPRE..extra_defines..extra_includes..source,"r")

        if not pipe then
            error("could not get file: "..err)
        end
        
        local iterator = cpp2ffi.location
        
        for line,locat in iterator(pipe,{locati},{},COMPILER) do
            --local line, comment = split_comment(line)
			parser2:insert(line,locat)
        end
        pipe:close()
    end
    parser2:do_parse()

    -- save ./cimgui_impl.h
    local cfuncsstr = func_header_impl_generate(parser2) 
    local cstructstr1,cstructstr2 = parser2:gen_structs_and_enums()
    save_data("./output/cimgui_impl.h",cstructstr1,cstructstr2,cfuncsstr)

    ----------save fundefs in impl_definitions.lua for using in bindings
    save_data("./output/impl_definitions.lua",serializeTableF(parser2.defsT))

end -- #implementations > 0 then

-------------------------------json saving
--avoid mixed tables (with string and integer keys)
local function json_prepare(defs)
    --delete signatures in function
    for k,def in pairs(defs) do
        for k2,v in pairs(def) do
            if type(k2)=="string" then
                def[k2] = nil
            end
        end
    end
    return defs
end
---[[
local json = require"json"
save_data("./output/definitions.json",json.encode(json_prepare(parser1.defsT)))
save_data("./output/structs_and_enums.json",json.encode(structs_and_enums_table))
save_data("./output/typedefs_dict.json",json.encode(parser1.typedefs_dict))
if parser2 then
    save_data("./output/impl_definitions.json",json.encode(json_prepare(parser2.defsT)))
end
--]]
-------------------copy C files to repo root
copyfile("./output/cimgui.h", "../cimgui.h")
copyfile("./output/cimgui.cpp", "../cimgui.cpp")
print"all done!!"
