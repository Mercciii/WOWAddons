-- =============================================
-- MercciiMacro v1.4.0 乌龟服可视化积木宏编辑器
-- 功能清单：
-- 积木拖拽画布｜可视化右侧参数面板｜IF分支无限嵌套
-- 职业分类模板｜宏搜索｜积木收藏置顶｜递归代码生成
-- 一键换装、导入导出、图标浏览器预留
-- =============================================
MercciiMacro = {}
local MOD = MercciiMacro

--===== 全局UI变量 =====
MOD.mainFrame = nil
MOD.macroListFrame = nil
MOD.canvasFrame = nil
MOD.paramPanel = nil
MOD.codeEditBox = nil
MOD.currentEditMacro = nil
MOD.iconBrowserFrame = nil

MOD.canvasBlockPool = {}
MOD.dragBlockIndex = nil
MOD.selectedCanvasBlockIndex = nil

MOD.branchEditDepth = 0
MOD.branchStack = {}
MOD.editingBranchIndex = nil

MOD.favoriteBlockList = {}
MOD.macroSearchText = ""

--===== 存档数据库 =====
MercciiMacroDB = MercciiMacroDB or {
    macroList = {},
    favoriteBlocks = {}
}
MOD.macroList = MercciiMacroDB.macroList
MOD.favoriteBlockList = MercciiMacroDB.favoriteBlocks

--########################
-- 🧩 积木注册表 ModuleRegistry
--########################
MOD.ModuleRegistry = {
    --施法模块
    hover_cast = {
        name = "悬停施法",
        desc = "优先鼠标悬停目标，无悬停则当前目标",
        category = "施法模块",
        args = {
            {key="spell",label="技能名称",default="治疗术"}
        },
        template = [[
if UnitExists("mouseover") then
    CastSpellByName("$spell","mouseover")
else
    CastSpellByName("$spell")
end]]
    },
    cast_target = {
        name = "对目标施法",
        desc = "直接对当前目标施放技能",
        category = "施法模块",
        args = {{key="spell",label="技能名称",default="寒冰箭"}},
        template = [[CastSpellByName("$spell")]]
    },
    cast_targettarget = {
        name = "目标的目标施法",
        desc = "对目标的目标施放技能（保护祝福等）",
        category = "施法模块",
        args = {{key="spell",label="技能名称",default="保护祝福"}},
        template = [[CastSpellByName("$spell","targettarget")]]
    },
    stopcasting = {
        name = "停止施法",
        desc = "打断当前读条",
        category = "施法模块",
        template = [[SpellStopCasting()]]
    },

    --物品模块
    use_item = {
        name = "使用物品",
        desc = "使用背包物品",
        category = "物品模块",
        args = {{key="item",label="物品名/ID",default="厚符文布绷带"}},
        template = [[UseItemByName("$item")]]
    },

    --宠物模块
    pet_summon = {
        name = "召唤宠物",
        desc = "猎人/术士召唤宠物",
        category = "宠物模块",
        args = {{key="spell",label="召唤技能",default="召唤虚空行者"}},
        template = [[CastSpellByName("$spell")]]
    },
    pet_dismiss = {
        name = "解散宠物",
        desc = "解散当前宠物",
        category = "宠物模块",
        template = [[DismissPet()]]
    },

    --提示模块
    chat_msg = {
        name = "聊天提示",
        desc = "聊天框输出文字",
        category = "提示模块",
        args = {{key="msg",label="提示文字",default="[宏执行完毕]"}},
        template = [[print("$msg")]]
    },

    --换装模块
    equip_set = {
        name = "一键换装套装",
        desc = "加载预设装备套装",
        category = "换装模块",
        args = {{key="setname",label="套装名称",default="防御套"}},
        template = [[MercciiMacro_EquipLoad("$setname")]]
    },

    --分支判定积木（支持嵌套）
    mod_key = {
        name = "修饰键分支",
        desc = "Shift/Ctrl/Alt 判定分支嵌套",
        category = "判定模块",
        isBranch = true,
        args = {
            {key="key",label="按键: shift / ctrl / alt",default="shift"}
        },
        template = [[
if Is$keyKeyDown() then
$branch1
else
$branch2
end]]
    },
    in_combat = {
        name = "战斗判定",
        desc = "是否处于战斗状态，可嵌套",
        category = "判定模块",
        isBranch = true,
        template = [[
if UnitAffectingCombat("player") then
$branch1
else
$branch2
end]]
    },
    hp_check = {
        name = "自身血量判定",
        desc = "玩家血量低于阈值执行分支",
        category = "判定模块",
        isBranch = true,
        args = {{key="pct",label="血量百分比",default="30"}},
        template = [[
if (UnitHealth("player")/UnitHealthMax("player"))*100 < $pct then
$branch1
else
$branch2
end]]
    },
    target_hp_check = {
        name = "目标血量判定",
        desc = "目标血量低于阈值执行分支",
        category = "判定模块",
        isBranch = true,
        args = {{key="pct",label="血量百分比",default="20"}},
        template = [[
if UnitExists("target") and ((UnitHealth("target")/UnitHealthMax("target"))*100 < $pct) then
$branch1
else
$branch2
end]]
    },
    buff_check = {
        name = "Buff检测",
        desc = "检测自身是否拥有指定Buff",
        category = "判定模块",
        isBranch = true,
        args = {{key="buffname",label="Buff名称",default="寒冰屏障"}},
        template = [[
if AuraUtil.FindAuraByName("$buffname","player") then
$branch1
else
$branch2
end]]
    },
    cooldown_check = {
        name = "冷却判定",
        desc = "技能是否冷却完毕",
        category = "判定模块",
        isBranch = true,
        args = {{key="spell",label="技能名称",default="冰箱"}},
        template = [[
if not GetSpellCooldown("$spell") then
$branch1
else
$branch2
end]]
    }
}

--########################
-- 📚 职业预设模板库
--########################
MOD.TemplateLib = {
    Priest = {
        {
            name = "悬停治疗术",
            tag = "治疗",
            icon = 135908,
            moduleChain = {
                {mod="hover_cast",args={spell="治疗术"}}
            }
        }
    },
    Warrior = {
        {
            name = "战斗判定绷带",
            tag = "生存",
            icon = 134400,
            moduleChain = {
                {
                    mod="in_combat",
                    args={},
                    branch1 = {
                        {mod="use_item",args={item="厚符文布绷带"}}
                    },
                    branch2 = {}
                }
            }
        }
    },
    Mage = {
        {
            name = "寒冰箭目标施法",
            tag = "输出",
            icon = 136076,
            moduleChain = {
                {mod="cast_target",args={spell="寒冰箭"}}
            }
        }
    },
    Rogue = {},
    Hunter = {},
    Shaman = {},
    Paladin = {},
    Warlock = {},
    Druid = {}
}

--########################
-- ✅【核心】递归嵌套代码生成器
--########################
function MOD:BuildCodeFromChain(chain, depth)
    if not chain then return "" end
    depth = depth or 0
    local indent = string.rep("    ", depth)
    local fullCode = ""

    for _,block in ipairs(chain) do
        local def = self.ModuleRegistry[block.mod]
        if not def then
            fullCode = fullCode..indent.."--[无效积木]"..block.mod.."\n"
            goto continue
        end

        local tpl = def.template or ""
        if block.args then
            for k,v in pairs(block.args) do
                tpl = string.gsub(tpl, "$"..k, v)
            end
        end

        if def.isBranch then
            local branch1Code = self:BuildCodeFromChain(block.branch1 or {}, depth+1)
            local branch2Code = self:BuildCodeFromChain(block.branch2 or {}, depth+1)
            tpl = string.gsub(tpl, "%$branch1", branch1Code)
            tpl = string.gsub(tpl, "%$branch2", branch2Code)
        end

        local lines = {}
        for line in tpl:gmatch("[^\n]+") do
            table.insert(lines, indent..line)
        end
        fullCode = fullCode..table.concat(lines,"\n").."\n"
        ::continue::
    end
    return fullCode
end

--########################
-- ✅【分支画布逻辑】
--########################
function MOD:GetCurrentBlockChain()
    if MOD.branchEditDepth == 0 then
        return MOD.currentEditMacro and MOD.currentEditMacro.moduleChain or nil
    end
    local b = MOD.branchStack[#MOD.branchStack]
    if b and b.branch then
        return b.branch
    end
    return MOD.currentEditMacro and MOD.currentEditMacro.moduleChain or nil
end

function MOD:EnterBranch(blockIdx)
    local chain = MOD:GetCurrentBlockChain()
    local block = chain[blockIdx]
    if not block then return end
    local def = MOD.ModuleRegistry[block.mod]
    if not def or not def.isBranch then return end

    if not block.branch then
        block.branch = {}
    end
    table.insert(MOD.branchStack, block)
    MOD.branchEditDepth = MOD.branchEditDepth + 1
    MOD.editingBranchIndex = blockIdx

    MOD.selectedCanvasBlockIndex = nil
    MOD:RefreshCanvas()
    MOD:RenderParamPanel()
    print("|cff00ff00✅ 进入分支层级："..MOD.branchEditDepth.."|r")
end

function MOD:LeaveBranch()
    if MOD.branchEditDepth <= 0 then return end
    table.remove(MOD.branchStack)
    MOD.branchEditDepth = MOD.branchEditDepth - 1
    MOD.editingBranchIndex = nil
    MOD.selectedCanvasBlockIndex = nil
    MOD:RefreshCanvas()
    MOD:RenderParamPanel()
    print("|cffffff00⬆ 返回上一层画布，当前层级："..MOD.branchEditDepth.."|r")
end

--########################
-- ✅【可视化参数面板渲染】
--########################
MOD.paramWidgetPool = {}
function MOD:RenderParamPanel()
    local p = MOD.paramPanel
    if not p then return end
    for _,w in ipairs(MOD.paramWidgetPool) do
        if w then w:Hide() end
    end
    MOD.paramWidgetPool = {}

    if not MOD.currentEditMacro or not MOD.selectedCanvasBlockIndex then
        local tip = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        tip:SetPoint("TOP",p,"TOP",0,-30)
        tip:SetText("👆 在画布点击积木\n即可编辑参数")
        table.insert(MOD.paramWidgetPool,tip)
        return
    end

    local blockIndex = MOD.selectedCanvasBlockIndex
    local block = MOD:GetCurrentBlockChain()[blockIndex]
    if not block then
        MOD.selectedCanvasBlockIndex = nil
        self:RenderParamPanel()
        return
    end
    local def = MOD.ModuleRegistry[block.mod]
    if not def then
        local tip = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        tip:SetPoint("TOP",p,"TOP",0,-30)
        tip:SetText("❌ 无效积木模块")
        table.insert(MOD.paramWidgetPool,tip)
        return
    end

    local title = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",p,"TOP",0,-30)
    title:SetText("📌 "..def.name)
    table.insert(MOD.paramWidgetPool,title)

    local desc = p:CreateFontString(nil,"OVERLAY","GameFontSmall")
    desc:SetPoint("TOP",title,"BOTTOM",0,-6)
    desc:SetTextColor(0.7,0.7,0.7)
    desc:SetText(def.desc)
    table.insert(MOD.paramWidgetPool,desc)

    if def.isBranch then
        local enterBranchBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
        enterBranchBtn:SetPoint("TOP",desc,"BOTTOM",0,-10)
        enterBranchBtn:SetWidth(140)
        enterBranchBtn:SetHeight(22)
        enterBranchBtn:SetText("📂 进入分支编辑")
        enterBranchBtn:SetScript("OnClick",function()
            MOD:EnterBranch(blockIndex)
        end)
        table.insert(MOD.paramWidgetPool,enterBranchBtn)
    end

    if not def.args or #def.args == 0 then
        local noArgTip = p:CreateFontString(nil,"OVERLAY","GameFontSmall")
        noArgTip:SetPoint("TOP",desc,"BOTTOM",0,-12)
        noArgTip:SetText("该积木无配置参数")
        table.insert(MOD.paramWidgetPool,noArgTip)
        return
    end

    local yPos = -60
    if def.isBranch then yPos = -95 end
    for _,argDef in ipairs(def.args) do
        local key = argDef.key
        local labelText = argDef.label
        local defaultValue = argDef.default
        local currentVal = block.args[key] or defaultValue

        local lbl = p:CreateFontString(nil,"OVERLAY","GameFontSmall")
        lbl:SetPoint("TOPLEFT",p,"TOPLEFT",12,yPos)
        lbl:SetText(labelText.."：")
        table.insert(MOD.paramWidgetPool,lbl)

        local eb = CreateFrame("EditBox",nil,p)
        eb:SetPoint("TOPLEFT",lbl,"BOTTOMLEFT",0,-4)
        eb:SetWidth(170)
        eb:SetHeight(20)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=16
        })
        eb:SetTextInsets(6,6,2,2)
        eb:SetText(currentVal)

        eb:SetScript("OnEditFocusLost",function()
            local newVal = eb:GetText()
            block.args[key] = newVal
            print("|cff00ff00参数已更新："..labelText.." = "..newVal.."|r")
        end)
        eb:SetScript("OnEnterPressed",function()
            eb:ClearFocus()
        end)

        table.insert(MOD.paramWidgetPool,eb)
        yPos = yPos - 36
    end
end

--########################
-- ✅【画布刷新｜拖拽积木】
--########################
function MOD:RefreshCanvas()
    if not MOD.canvasFrame then return end
    local scrollChild = MOD.canvasFrame.scrollChild
    for _,c in ipairs({scrollChild:GetChildren()}) do c:Hide() end
    MOD.canvasBlockPool = {}

    local chain = MOD:GetCurrentBlockChain()
    if not chain then
        MOD.selectedCanvasBlockIndex = nil
        MOD:RenderParamPanel()
        return
    end
    local yOffset = -5
    for idx,block in ipairs(chain) do
        local def = MOD.ModuleRegistry[block.mod]
        local b = CreateFrame("Button",nil,scrollChild,"UIPanelButtonTemplate")
        b:SetWidth(290)
        b:SetHeight(26)
        b:SetPoint("TOPLEFT",scrollChild,"TOPLEFT",10,yOffset)
        b:SetText(def and def.name or "无效积木")
        b.blockIndex = idx

        if MOD.selectedCanvasBlockIndex == idx then
            b:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12
            })
            b:SetBackdropColor(0.2,0.6,0.2,0.35)
        end

        b:SetScript("OnClick",function()
            MOD.selectedCanvasBlockIndex = idx
            MOD:RefreshCanvas()
            MOD:RenderParamPanel()
        end)

        b:SetScript("OnMouseDown",function()
            MOD.dragBlockIndex = this.blockIndex
        end)
        b:SetScript("OnMouseUp",function()
            if MOD.dragBlockIndex then
                local src = MOD.dragBlockIndex
                local dst = this.blockIndex
                local c = MOD:GetCurrentBlockChain()
                c[src],c[dst] = c[dst],c[src]
                MOD:RefreshCanvas()
                MOD:RenderParamPanel()
            end
            MOD.dragBlockIndex = nil
        end)

        local del = CreateFrame("Button",nil,scrollChild,"UIPanelButtonTemplate")
        del:SetWidth(22)
        del:SetHeight(22)
        del:SetPoint("LEFT",b,"RIGHT",4,0)
        del:SetText("×")
        del:SetScript("OnClick",function()
            if MOD.selectedCanvasBlockIndex == idx then
                MOD.selectedCanvasBlockIndex = nil
            end
            local c = MOD:GetCurrentBlockChain()
            table.remove(c,idx)
            MOD:RefreshCanvas()
            MOD:RenderParamPanel()
        end)

        table.insert(MOD.canvasBlockPool,b)
        yOffset = yOffset - 30
    end
    scrollChild:SetHeight(math.abs(yOffset)+10)
end

--########################
-- ✅【宏列表刷新，支持搜索过滤】
--########################
function MOD:RefreshMacroList()
    if not MOD.macroListFrame then return end
    for _,c in ipairs({MOD.macroListFrame:GetChildren()}) do c:Hide() end
    local y = -10
    for _,macro in ipairs(MOD.macroList) do
        local keyword = MOD.macroSearchText:lower()
        local match = true
        if keyword ~= "" then
            match = false
            if macro.name:lower():find(keyword) then match = true end
            if macro.tag and macro.tag:lower():find(keyword) then match = true end
        end
        if not match then goto continue end

        local b = CreateFrame("Button",nil,MOD.macroListFrame,"UIPanelButtonTemplate")
        b:SetWidth(160)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT",MOD.macroListFrame,"TOPLEFT",10,y)
        b:SetText(macro.name)
        b.macroData = macro
        b:SetScript("OnClick",function()
            MOD.currentEditMacro = macro
            MOD.selectedCanvasBlockIndex = nil
            MOD:RefreshCanvas()
            MOD:RenderParamPanel()
            if MOD.codeEditBox then
                MOD.codeEditBox:SetText(macro.rawCode or "")
            end
        end)
        y = y - 26
        ::continue::
    end
end

--########################
-- ✅【积木选择弹窗：添加积木到画布】
--########################
function MOD:ShowAddBlockPopup()
    StaticPopupDialogs["MERCCII_ADD_BLOCK"] = {
        text = "输入积木名称添加积木\n悬停施法 / 对目标施法 / 战斗判定 / hp_check",
        button1 = "添加",
        button2 = "关闭",
        hasEditBox = true,
        OnAccept = function()
            local input = getglobal(this:GetName().."EditBox"):GetText()
            local findKey = nil
            for k,v in pairs(MOD.ModuleRegistry) do
                if v.name == input then
                    findKey = k
                    break
                end
            end
            if not findKey then
                print("|cffff0000找不到该积木！名称严格匹配|r")
                return
            end
            if not MOD.currentEditMacro then
                print("|cffff0000请先选中一条宏|r")
                return
            end
            local def = MOD.ModuleRegistry[findKey]
            local newBlock = {mod=findKey,args={}}

            if def.args then
                for _,argDef in ipairs(def.args) do
                    newBlock.args[argDef.key] = argDef.default
                end
            end

            if def.isBranch then
                newBlock.branch1 = {}
                newBlock.branch2 = {}
            end

            local chain = MOD:GetCurrentBlockChain()
            table.insert(chain,newBlock)
            MOD.selectedCanvasBlockIndex = #chain
            MOD:RefreshCanvas()
            MOD:RenderParamPanel()
            print("|cff00ff00积木【"..def.name.."】已追加至画布|r")
        end
    }
    StaticPopup_Show("MERCCII_ADD_BLOCK")
end

--########################
-- ✅【职业分类模板加载弹窗】
--########################
function MOD:ShowTemplatePicker()
    StaticPopupDialogs["MERCCII_CLASS_SELECT"] = {
        text = "=== 选择职业 ===\n1 牧师\n2 战士\n3 法师\n4 盗贼\n5 猎人\n6 萨满\n7 圣骑士\n8 术士\n9 德鲁伊\n输入职业编号：",
        button1 = "下一步",
        button2 = "取消",
        hasEditBox = true,
        maxLetters = 1,
        OnAccept = function()
            local classNum = tonumber(StaticPopup_EditBox:GetText())
            local classMap = {
                [1] = "Priest",[2] = "Warrior",[3] = "Mage",
                [4] = "Rogue",[5] = "Hunter",[6] = "Shaman",
                [7] = "Paladin",[8] = "Warlock",[9] = "Druid"
            }
            local classKey = classMap[classNum]
            if not classKey or not MOD.TemplateLib[classKey] then
                print("|cffff4444职业编号无效！|r")
                return
            end
            local list = MOD.TemplateLib[classKey]
            local str = "=== "..classKey.." 模板 ===\n"
            for i,v in ipairs(list) do str = str..i.." "..v.name.."\n" end
            str = str.."输入模板编号载入："

            StaticPopupDialogs["MERCCII_TPL_SELECT"] = {
                text = str,
                button1 = "载入模板",
                button2 = "返回上一步",
                hasEditBox = true,
                maxLetters = 2,
                OnAccept = function()
                    local tid = tonumber(StaticPopup_EditBox:GetText())
                    local sel = list[tid]
                    if not sel then print("|cffff4444模板编号无效|r") return end
                    local nm = {
                        name = sel.name,
                        tag = sel.tag,
                        icon = sel.icon,
                        moduleChain = {},
                        rawCode = ""
                    }
                    for _,blk in ipairs(sel.moduleChain) do
                        table.insert(nm.moduleChain, MOD:DeepCopy(blk))
                    end
                    table.insert(MOD.macroList, nm)
                    MOD:RefreshMacroList()
                    print("|cff00ff00模板已导入："..nm.name.."|r")
                end,
                OnCancel = function()
                    MOD:ShowTemplatePicker()
                end
            }
            StaticPopup_Show("MERCCII_TPL_SELECT")
        end
    }
    StaticPopup_Show("MERCCII_CLASS_SELECT")
end

--深拷贝工具函数
function MOD:DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[MOD:DeepCopy(orig_key)] = MOD:DeepCopy(orig_value)
        end
        setmetatable(copy, MOD:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

--########################
-- ✅【UI主窗口完整创建】
--########################
function MOD:CreateMainFrame()
    local f = CreateFrame("Frame","MercciiMacroMainFrame",UIParent)
    f:SetWidth(920)
    f:SetHeight(620)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })
    f:SetBackdropColor(0.1,0.1,0.1,0.92)
    f:Hide()
    MOD.mainFrame = f

    --标题
    local title = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",f,"TOP",0,-12)
    title:SetText("MercciiMacro |cff00ccff积木可视化宏编辑器 v1.4.0|r")

    --关闭按钮
    local closeBtn = CreateFrame("Button",nil,f,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",f,"TOPRIGHT",-5,-5)

    --===== 左侧：宏列表面板 =====
    local leftPanel = CreateFrame("Frame",nil,f)
    leftPanel:SetWidth(180)
    leftPanel:SetHeight(520)
    leftPanel:SetPoint("TOPLEFT",f,"TOPLEFT",12,-45)
    leftPanel:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })
    local listTitle = leftPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    listTitle:SetPoint("TOP",leftPanel,"TOP",0,-8)
    listTitle:SetText("📋 宏列表")

    MOD.macroListFrame = CreateFrame("Frame",nil,leftPanel)
    MOD.macroListFrame:SetWidth(160)
    MOD.macroListFrame:SetHeight(440)
    MOD.macroListFrame:SetPoint("TOP",leftPanel,"TOP",0,-30)

    --新建宏按钮
    local btnNewMacro = CreateFrame("Button",nil,leftPanel,"UIPanelButtonTemplate")
    btnNewMacro:SetPoint("BOTTOMLEFT",leftPanel,"BOTTOMLEFT",8,8)
    btnNewMacro:SetWidth(75)
    btnNewMacro:SetHeight(22)
    btnNewMacro:SetText("新建宏")
    btnNewMacro:SetScript("OnClick",function()
        local newM = {
            name = "新宏"..(#MOD.macroList+1),
            tag = "",
            icon = 134400,
            moduleChain = {},
            rawCode = ""
        }
        table.insert(MOD.macroList,newM)
        MOD:RefreshMacroList()
    end)

    local btnLoadTpl = CreateFrame("Button",nil,leftPanel,"UIPanelButtonTemplate")
    btnLoadTpl:SetPoint("BOTTOMRIGHT",leftPanel,"BOTTOMRIGHT",-8,8)
    btnLoadTpl:SetWidth(75)
    btnLoadTpl:SetHeight(22)
    btnLoadTpl:SetText("模板库")
    btnLoadTpl:SetScript("OnClick",function() MOD:ShowTemplatePicker() end)

    --===== 中间画布区域 =====
    local midPanel = CreateFrame("Frame",nil,f)
    midPanel:SetWidth(460)
    midPanel:SetHeight(520)
    midPanel:SetPoint("LEFT",leftPanel,"RIGHT",12,0)
    midPanel:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })
    local canvasTitle = midPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    canvasTitle:SetPoint("TOP",midPanel,"TOP",0,-8)
    canvasTitle:SetText("🧩 积木画布（拖拽排序）")

    MOD.canvasFrame = CreateFrame("ScrollFrame",nil,midPanel,"UIPanelScrollFrameTemplate")
    MOD.canvasFrame:SetWidth(420)
    MOD.canvasFrame:SetHeight(410)
    MOD.canvasFrame:SetPoint("TOP",midPanel,"TOP",0,-30)
    MOD.canvasFrame.scrollChild = CreateFrame("Frame",nil,MOD.canvasFrame)
    MOD.canvasFrame.scrollChild:SetWidth(410)
    MOD.canvasFrame:SetScrollChild(MOD.canvasFrame.scrollChild)

    --画布底部按钮
    local btnAddBlock = CreateFrame("Button",nil,midPanel,"UIPanelButtonTemplate")
    btnAddBlock:SetPoint("BOTTOMLEFT",midPanel,"BOTTOMLEFT",10,10)
    btnAddBlock:SetWidth(100)
    btnAddBlock:SetHeight(22)
    btnAddBlock:SetText("➕ 添加积木")
    btnAddBlock:SetScript("OnClick",function() MOD:ShowAddBlockPopup() end)

    local btnBackBranch = CreateFrame("Button",nil,midPanel,"UIPanelButtonTemplate")
    btnBackBranch:SetPoint("BOTTOM",midPanel,"BOTTOM",0,10)
    btnBackBranch:SetWidth(100)
    btnBackBranch:SetHeight(22)
    btnBackBranch:SetText("⬆ 返回上层")
    btnBackBranch:SetScript("OnClick",function() MOD:LeaveBranch() end)

    local btnGenCode = CreateFrame("Button",nil,midPanel,"UIPanelButtonTemplate")
    btnGenCode:SetPoint("BOTTOMRIGHT",midPanel,"BOTTOMRIGHT",-10,10)
    btnGenCode:SetWidth(110)
    btnGenCode:SetHeight(22)
    btnGenCode:SetText("🔨积木生成代码")
    btnGenCode:SetScript("OnClick",function()
        if not MOD.currentEditMacro then
            print("|cffff4444请选中宏！|r")
            return
        end
        local code = MOD:BuildCodeFromChain(MOD.currentEditMacro.moduleChain)
        MOD.currentEditMacro.rawCode = code
        if MOD.codeEditBox then
            MOD.codeEditBox:SetText(code)
        end
        print("|cff00ff00✅代码生成完毕！|r")
    end)

    --===== 右侧参数面板 =====
    local rightPanel = CreateFrame("Frame",nil,f)
    rightPanel:SetWidth(220)
    rightPanel:SetHeight(520)
    rightPanel:SetPoint("LEFT",midPanel,"RIGHT",12,0)
    rightPanel:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })
    local paramTitle = rightPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    paramTitle:SetPoint("TOP",rightPanel,"TOP",0,-8)
    paramTitle:SetText("⚙️ 参数面板")
    MOD.paramPanel = rightPanel

    --===== 底部代码预览框 =====
    local codePanel = CreateFrame("Frame",nil,f)
    codePanel:SetWidth(890)
    codePanel:SetHeight(100)
    codePanel:SetPoint("TOPLEFT",f,"BOTTOMLEFT",12,-12)
    codePanel:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })
    local codeTitle = codePanel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    codeTitle:SetPoint("TOPLEFT",codePanel,"TOPLEFT",10,-6)
    codeTitle:SetText("📜 生成Lua代码预览")

    MOD.codeEditBox = CreateFrame("EditBox",nil,codePanel)
    MOD.codeEditBox:SetWidth(860)
    MOD.codeEditBox:SetHeight(70)
    MOD.codeEditBox:SetPoint("TOP",codePanel,"TOP",0,-20)
    MOD.codeEditBox:SetMultiLine(true)
    MOD.codeEditBox:SetAutoFocus(false)
    MOD.codeEditBox:SetFontObject("GameFontNormalSmall")
    MOD.codeEditBox:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16
    })

    MOD:RefreshMacroList()
    MOD:RenderParamPanel()
end

--########################
-- ✅【命令行 /merccii 打开面板】
--########################
SLASH_MERCCIIMACRO1 = "/merccii"
SLASH_MERCCIIMACRO2 = "/mercciimacro"
SlashCmdList["MERCCIIMACRO"] = function(msg)
    if not MOD.mainFrame then
        MOD:CreateMainFrame()
    end
    if MOD.mainFrame:IsShown() then
        MOD.mainFrame:Hide()
    else
        MOD.mainFrame:Show()
    end
end

--插件载入事件
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent",function()
    if event == "ADDON_LOADED" and arg1 == "MercciiMacro" then
        MOD.macroList = MercciiMacroDB.macroList
        MOD.favoriteBlockList = MercciiMacroDB.favoriteBlocks
        print("|cff00ccffMercciiMacro v1.4.0 加载完成 | 输入 /merccii 打开编辑器|r")
    end
end)
