--[[���������Lua5.0���еĲ���ʽ���ҳ�����ֱ��������ݹ�ķ��ս��--]]

require("common.lua")
require("set.lua")
require("list.lua")
require("prototype.lua")

--[[----------------------------------------------------------
--          helper functions
----------------------------------------------------------]]--

-- str: ���������ַ���
-- start: ��������ʼλ��(��1��ʼ����)
-- ��������: ����ʱ�õ���ƥ��ģʽ
-- �������θ���ÿ��ģʽ��startλ�ÿ�ʼ����str����������ƥ���ģʽ����Լ�
-- ƥ������ַ�������ʼ���ս�λ�ã����ָ����capture�᷵����Ӧ��substring
local function SearchByOr(str,start,...)
   local result
   for i = 1,arg.n do
      result = pack(string.find(str,arg[i],start))
      if nil ~= result[1] then
	 --���ݵ�n��pattern�ҵ���ƥ������ַ���
	 return i,unpack(result)
      end
   end
   --���е�pattern���޷��ɹ�ƥ��
   return nil
end

--[[----------------------------------------------------------
--          helper functions end
--]]----------------------------------------------------------



--[[----------------------------------------------------------
          internal functions
--]]----------------------------------------------------------

local function CreateRightside(rsStr)
   if 0 == string.len(rsStr) then
      error("Production's rightside string can't be empty!")
   end

   local rs = Rightside{}
   local nextPos = 1,symbol,patIndex
   local rsStrLen = string.len(rsStr)
   local allSymbols = Set{}
   
   while nextPos <= rsStrLen  do
      patIndex, _,nextPos,symbol = 
	 SearchByOr(
		    rsStr,nextPos,
		    "^%s*([_%a][_%w]*)",
		    "^%s*(%b'')")

      if 1 == patIndex then
	 rs:Append(symbol)
	 allSymbols:Add(symbol)
      elseif 2 == patIndex then
	 symbol = string.sub(symbol,2,-2)
	 rs:Append(symbol)
	 allSymbols:Add(symbol)
      else
	 -- error : invalid format
	 return nil
      end
      
      nextPos = nextPos + 1
   end

   return rs,allSymbols
end


-- ���ݵ�ǰ�Ѿ�����õ�First��������:firstset
-- �������﷨����symbol�µ�First;
-- ���������firstset�С�
-- ����ڼ��������firstset�ı��ˣ�
-- �򷵻�true�����򷵻�false
local function EvaluateFirstOfSymbol(symbol,productions,firstset)
   if nil == firstset[symbol] then
      firstset[symbol] = Set{}
   end
   
   local rightsides = productions[symbol]
   if nil == rightsides then
      --symbol���ս��
      if firstset[symbol]:Empty() then
	 return firstset[symbol]:Add(symbol)
      end
      
      return false
   end

   local bChanged = false
   for rightside in rightsides:Traverse() do
      local bCanBeEmpty = true
      for _,leftmost in rightside:Traverse() do
	 if nil ~= firstset[leftmost] then
	    bChanged = firstset[symbol]:Union(firstset[leftmost] 
					      - Set{"empty"})
	       or bChanged
	    if not firstset[leftmost]:Contains("empty") then
	       bCanBeEmpty = false
	       break
	    end
	 else
	    bCanBeEmpty = false
	    break
	 end
      end
      
      if bCanBeEmpty then
	 -- righside�����з��ŵ�first�����ж��� "empty"��
	 -- ��ô��symbol��first������ҲҪ����"empty"
	 bChanged = firstset[symbol]:Add("empty")
	    or bChanged
      end
   end
   
   return bChanged
end

local function EvaluateFirst(syntax)
   local firstset = syntax.firstset or {}
   local allsymbols = syntax.nonterminals + syntax.terminals
   local productions = syntax.productions
   
   local bChanged = true
   while bChanged do
      bChanged = false
      for symbol in allsymbols:Traverse() do
	 bChanged = 
	    EvaluateFirstOfSymbol(symbol,productions,firstset)
	    or bChanged
      end
   end

   return firstset
end

local function EvaluateFollowOnePass(syntax,followset)
   local productions = syntax.productions
   local firstset = syntax.firstset
   local bChanged = false
   
   for nonterminal,rightsides in pairs(productions) do
      followset[nonterminal] =
	 followset[nonterminal] or Set{}
      
      if nonterminal == syntax.start then
	 --nonterminal����ʼ��
	 bChanged = followset[nonterminal]:Add("eof")
	    or bChanged
      end
      
      for rightside in rightsides:Traverse() do
	 for i,symbol in rightside:Traverse() do
	    if nil ~= productions[symbol] then
	       --symbol�Ƿ��ս��
	       followset[symbol] = 
		  followset[symbol] or Set{}
	       local tailset = 
		  GetLeadingsOfRightside(rightside:Sub(i + 1),firstset)
	       
	       bChanged = followset[symbol]:Union(tailset - Set{"empty"})
		  or bChanged
	       if tailset:Contains("empty") then
		  bChanged = followset[symbol]:Union(followset[nonterminal])
		     or bChanged
	       end
	    end
	 end
      end
   end

   return bChanged
end

local function EvaluateFollow(syntax)
   local firstset = syntax.firstset
   local followset = syntax.followset or {}
   
   local bChanged = true
   while bChanged do
      bChanged = false
      bChanged = EvaluateFollowOnePass(syntax,followset)
	 or bChanged
   end
   
   return followset
end

local function GetSelect(nonterminal,rs,firstset,followset)
   local select = GetLeadingsOfRightside(rs,firstset)
   if select:Contains("empty") then
      select:Union(followset[nonterminal])
   end

   return select
end

local function AnalyseProductions(stream)
   local all_symbols = Set{}
   local all_nts = Set{}
   local productions = {}
   local syntax = {}
   syntax.productions = productions
   syntax.nonterminals = all_nts

   local nonterminal

   for line in stream:lines() do
      local _,ls_end,ls_str = string.find(line,"^%s*([_%a][_%w]*)%s*:")
      if nil ~= ls_str then
	 -- ����һ���µķ��ս��
	 nonterminal = ls_str
	 syntax.start = syntax.start or nonterminal
	 all_nts:Add(nonterminal)
	 productions[nonterminal] = 
	    productions[nonterminal] or Set{}
      end
      
      local rs_beg,rs_end,rs_str
      if nil ~= ls_end then
	 rs_beg = ls_end + 1
      else
	 rs_beg = 1
      end
      
      rs_beg,rs_end,rs_str = string.find(line,"%s*([^|]*[^|%s])",rs_beg + 1)
      while rs_beg ~= nil do
	 if not IsSpaceStr(rs_str) then
	    --�ҵ�һ���µ��Ҳ�
	    local rs,symbols = CreateRightside (rs_str)
	    if nil == rs then
	       -- �����ϸ�ʽҪ����﷨����
	       return nil
	    end
	    all_symbols:Union(symbols)
	    productions[nonterminal]:Add(rs)
	 end
	 rs_beg,rs_end,rs_str = string.find(line,"%s*([^|]*[^|%s])",rs_end + 1)
      end
   end

   syntax.terminals = all_symbols - all_nts
   
   return syntax
end

-- ����һ��item���ϵıհ�
local function Closure(syntax,items)
   local res = Set{}
   local productions = syntax.productions
   res:Union(items)
   local newitems = res

   local bChanged = true

   while bChanged do
      bChanged = false
      local temp = Set{}
      for item in newitems:Traverse() do
	 local symbol = item:NextSymbol()
	 if symbol and productions[symbol] then
	    --symbol��һ�����ս��
	    local rightsides = productions[symbol]
	    for rs in rightsides:Traverse() do
	       temp:Add(Item.New(symbol,rs))
	    end
	 end
      end
      newitems = temp
      bChanged = res:Union(newitems) or bChanged
   end

   return res
end

local function Goto(syntax,items,symbol)
   local temp = Set{}
   for item in items:Traverse() do
      local newitem = item:Goto(symbol)
      if newitem then
	 temp:Add(newitem)
      end
   end
   
   return Closure(syntax,temp)
end

-- ����syntax���ʼ��item���ϱհ�
local function InitialItems(syntax)
   local start = syntax.start
   local rightsides = syntax.productions[start]
   local items = Set{}
   for rs in rightsides:Traverse() do
      items:Add(Item.New(start,rs))
   end
   
   return Closure(syntax,items)
end

-- ����һ��item���ϵ����е�next����
local function NextSymbols(items)
   local res = Set{}
   for item in items:Traverse() do
      res:Add(item:NextSymbol())
   end

   return res
end

--[[----------------------------------------------------------
--          internal functions end
--]]----------------------------------------------------------

function GetLeadingsOfRightside(rs,firstset)
   local res = Set{"empty"}
   for _,symbol in rs:Traverse() do
      res:Union(firstset[symbol])
      if not firstset[symbol]:Contains("empty") then
	 res:Remove("empty")
	 break
      end
   end

   return res
end

function AnalyseSyntax(stream,basicFirstset,basicFollowset)
   local syntax = AnalyseProductions(stream)
   if nil == syntax then
      return nil
   end
   syntax.firstset = basicFirstset
   syntax.followset = basicFollowset

   syntax.firstset = EvaluateFirst(syntax)
   syntax.followset = EvaluateFollow(syntax)
   return syntax
end

-- ��������select�����г�ͻ�Ĳ���ʽ;
-- ���syntax��LL1�﷨���򲻻��г�ͻ
function get_ll_conflict(syntax)
   local productions = syntax.productions
   local firstset = syntax.firstset
   local followset = syntax.followset
   local conflict = List{}

   for nonterminal,rightsides in pairs(productions) do
      for rs1 in rightsides:Traverse() do
	 local select1 = GetSelect(nonterminal,
				   rs1,
				   firstset,
				   followset)
	 
	 for rs2 in rightsides:Traverse() do
	    if rs1 ~= rs2 then
	       local select2 = GetSelect(nonterminal,
					 rs2,
					 firstset,
					 followset)
	       local intersect = (select1 * select2)
	       if not intersect:Empty() then
		  conflict:Append(List{nonterminal,rs1,rs2,intersect})
	       end
	    end
	 end
      end
   end
   
   if conflict:Empty() then
      return nil
   end

   return conflict
end

-- �ú�������syntax��SLR������, ÿ��entry�ü��������棬
-- ��˼�ʹ�г�ͻҲ�������������ꡣ
-- ����ֵ1����syntax�Ƿ�ΪSLR�﷨
-- ����ֵ2���Ǹ�syntax��SLR������
function EvaluateSlr(syntax)
   local collection = List{}
   collection:Append(InitialItems(syntax))
   
   local bChanged = true
   local res = true		--
   local old_count = 0
   local newcollection = collection
   local pt = ParseTable.New()
   local followset = syntax.followset
   -- ��ʼ����ĳ��symbolʱһ���Ϸ��ĳ���(��ʼ)״̬
   local initialStates = {}

   while bChanged do
      bChanged = false
      local temp = List{}
      
      for i,items in newcollection:Traverse() do
	 -- ��ǰ���ڴ����items��collection�е�ȷ��λ����i + old_count
	 local items_pos = i + old_count
	 for item in items:Traverse() do
	    local next_symbol = item:NextSymbol()
	    if next_symbol then
	       local goto_items = Goto(syntax,items,next_symbol)
	       --����goto_items��collection�е�λ��
	       local goto_pos = 
		  collection:Find(goto_items)
			       
	       if nil == goto_pos then
		  -- ���goto_items��collection�в�����,
		  -- �������temp��Ѱ��
		  local temp_pos = temp:Find(goto_items)
		  if nil == temp_pos then
		     -- goto_items��temp��Ҳ������
		     -- ������ӽ�temp
		     temp:Append(goto_items)
		     temp_pos = temp:Count()
		  end
		  -- ����goto_items��collection�е�ȷ��λ��
		  goto_pos = temp_pos + collection:Count()
	       end
	       pt:Add(items_pos,next_symbol,goto_pos)
	       -- 
	       initialStates[next_symbol] = 
		  initialStates[next_symbol] or items_pos
	       if 1 < pt:Get(items_pos,next_symbol):Count() then
		  res = false
	       end
	    else -- if next_symbol then
	       local ls = item:GetLeftside()
	       if ls == syntax.start then
		  -- slr����(start����,"eof")��Ӧ����������������
		  -- ��̫һ����������Ϊopnelua�ı�����Ϊ��һ�����⡣
		  pt:Add(items_pos,"eof",item:GetProduction())
		  initialStates["eof"] = 
		     initialStates["eof"] or items_pos
		  if 1 < pt:Get(items_pos,"eof"):Count() then
		     res = false
		  end
	       else
		  local follow = followset[ls]
		  for terminal in follow:Traverse() do
		     pt:Add(items_pos,terminal,item:GetProduction())
		     initialStates[terminal] = 
			initialStates[terminal] or items_pos
		     if 1 < pt:Get(items_pos,terminal):Count() then
			res = false
		     end
		  end
	       end
	    end -- if next_symbol then
	 end
      end
      
      if not temp:Empty() then
	 bChanged = true
	 newcollection = temp
	 old_count = collection:Count()
	 collection = collection..newcollection
      end
   end

   -- ���start���ŵ�һ���������
   pt:Add(1,syntax.start,0)
   initialStates[syntax.start] = 
      initialStates[syntax.start] or 1
   
   return res,pt,initialStates
end

-- �ú�������syntax���ϸ�SLR������, ÿ��entry�������г�ͻ��
-- ����ֵ1����syntax�Ƿ�ΪSLR�﷨���������ֵΪtrueʱ�����еڶ�������ֵ
-- ����ֵ2���Ǹ�syntax��SLR������
function EvaluateStrictSlr(syntax)
   local collection = List{}
   collection:Append(InitialItems(syntax))
   
   local bChanged = true
   local old_count = 0
   local newcollection = collection
   local slr = {}
   local followset = syntax.followset

   while bChanged do
      bChanged = false
      local temp = List{}
      
      for i,items in newcollection:Traverse() do
	 -- ��ǰ���ڴ����items��collection�е�ȷ��λ����i + old_count
	 local items_pos = i + old_count
	 for item in items:Traverse() do
	    local next_symbol = item:NextSymbol()
	    if next_symbol then
	       local goto_items = Goto(syntax,items,next_symbol)
	       --����goto_items��collection�е�λ��
	       local goto_pos = 
		  collection:Find(goto_items)
			       
	       if nil == goto_pos then
		  -- ���goto_items��collection�в�����,
		  -- �������temp��Ѱ��
		  local temp_pos = temp:Find(goto_items)
		  if nil == temp_pos then
		     -- goto_items��temp��Ҳ������
		     -- ������ӽ�temp
		     temp:Append(goto_items)
		     temp_pos = temp:Count()
		  end
		  -- ����goto_items��collection�е�ȷ��λ��
		  goto_pos = temp_pos + collection:Count()
	       end
	       
	       --slr:Add(items_pos,next_symbol,goto_pos)
	       slr[items_pos] = slr[items_pos] or {}
	       if nil ~= slr[items_pos][next_symbol] then
		  -- �г�ͻ����Ȼ����SLR�﷨
		  return false
	       end
	       slr[items_pos][next_symbol] = goto_pos;
	    else -- if next_symbol then
	       local ls = item:GetLeftside()
	       if ls == syntax.start then
		  slr[items_pos] = slr[items_pos] or {}
		  if nil ~= slr[items_pos]["eof"] then
		     -- �г�ͻ����Ȼ����SLR�﷨
		     return false
		  end
		  -- slr����(start����,"eof")��Ӧ����������������
		  -- ��̫һ����������Ϊopnelua�ı�����Ϊ��һ�����⡣
		  slr[items_pos]["eof"] = item:GetProduction()
	       else
		  local follow = followset[ls]
		  for terminal in follow:Traverse() do
		     slr[items_pos] = slr[items_pos] or {}
		     if nil ~= slr[items_pos][terminal] then
			return false
		     end
		     slr[items_pos][terminal] = item:GetProduction()
		  end
	       end
	    end
	 end
      end
      
      if not temp:Empty() then
	 bChanged = true
	 newcollection = temp
	 old_count = collection:Count()
	 collection = collection..newcollection
      end
   end
   
   -- ���start���ŵ�һ���������
   slr[1][syntax.start] = 0
   return true,slr
end

-- �������ظ����ַ���str�������slr���������strָ�����﷨����SLR�﷨��
-- �򷵻�nil���˺�����Ҫ�ṩ�����׫д��ʹ�á�
function ToStrictRule(input)
   if "string" == type(input) then
      input = IStream.New(input)
   end
   local syntax = AnalyseSyntax(input)
   local bSlr, slr = EvaluateStrictSlr(syntax)
   if bSlr then
      return slr
   end

   return nil
end