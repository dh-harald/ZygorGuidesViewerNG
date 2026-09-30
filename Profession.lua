-- Current and maximum rank of a skill line by its English name (a weapon skill or a
-- profession), 0 and 0 when it is not learned. Only skill lines under an expanded header are
-- listed by GetSkillLineInfo.
function ZGV:GetSkillRank(name)
    for i = 1, (GetNumSkillLines() or 0) do
        local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if skillName == name and not isHeader then return skillRank or 0, skillMaxRank or 0 end
    end
    return 0, 0
end
