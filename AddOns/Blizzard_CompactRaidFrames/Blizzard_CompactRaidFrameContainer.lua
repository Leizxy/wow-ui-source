MAX_RAID_GROUPS = 8;

--Widget Handlers
function CompactRaidFrameContainer_OnLoad(self)
	FlowContainer_Initialize(self);	--Congrats! We are now a certified FlowContainer.
	
	self.units = {--[["raid1", "raid2", "raid3", ..., "raid40"]]};
	for i=1, MAX_RAID_MEMBERS do
		tinsert(self.units, "raid"..i);
	end
	
	self:RegisterEvent("RAID_ROSTER_UPDATE");
	self:RegisterEvent("UNIT_PET");
	
	self.frameReservations = {
		raid		= CompactRaidFrameReservation_NewManager();
		pet		= CompactRaidFrameReservation_NewManager();
		flagged	= CompactRaidFrameReservation_NewManager();	--For Main Tank/Assist units
		target	= CompactRaidFrameReservation_NewManager();	--Target of target for Main Tank/Main Assist
	}

	self.unitFrameUnusedFunc = function(frame)
													CompactUnitFrame_SetUnit(frame, nil);
													frame.inUse = false;
												end;
												
	CompactRaidFrameContainer_SetFlowFilterFunction(self, function(token) return UnitExists(token) end)
	self.displayPets = true;
	self.displayFlaggedMembers = true;
end

function CompactRaidFrameContainer_OnEvent(self, event, ...)
	if ( event == "RAID_ROSTER_UPDATE" ) then
		CompactRaidFrameContainer_TryUpdate(self);
	elseif ( event == "UNIT_PET" ) then
		if ( self.displayPets ) then
			local unit = ...;
			if ( strfind(unit, "raid%d+$") ) then
				CompactRaidFrameContainer_TryUpdate(self);
			end
		end
	end
end

function CompactRaidFrameContainer_OnSizeChanged(self)
	FlowContainer_DoLayout(self);
end

--Externally used functions
function CompactRaidFrameContainer_SetGroupMode(self, groupMode)
	self.groupMode = groupMode;
	CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowFilterFunction(self, flowFilterFunc)
	--Usage: flowFilterFunc is called as flowFilterFunc("unittoken") and should return whether this frame should be displayed or not.
	self.flowFilterFunc = flowFilterFunc;
	CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowSortFunction(self, flowSortFunc)
	--Usage: Takes two tokens, should work as a Lua sort function.
	--The ordering must be well-defined, even across units that will be filtered out
	self.flowSortFunc = flowSortFunc;
	CompactRaidFrameContainer_TryUpdate(self);
end

--Internally used functions
function CompactRaidFrameContainer_TryUpdate(self)
	if ( CompactRaidFrameContainer_ReadyToUpdate(self) ) then
		CompactRaidFrameContainer_LayoutFrames(self);
	end
end

function CompactRaidFrameContainer_ReadyToUpdate(self)
	if ( not self.groupMode ) then
		return false;
	end
	if ( self.groupMode == "flush" and not (self.flowFilterFunc and self.flowSortFunc) ) then
		return false;
	end
	return true;
end

function CompactRaidFrameContainer_LayoutFrames(self)
	--First, hide everything we currently use.
	for i=1, #self.flowFrames do
		if ( type(self.flowFrames[i]) == "table" and self.flowFrames[i].unusedFunc ) then
			self.flowFrames[i]:unusedFunc();
		end
	end
	FlowContainer_RemoveAllObjects(self);
	
	FlowContainer_PauseUpdates(self);	--We don't want to update it every time we add an item.
	
	
	if ( self.displayFlaggedMembers ) then
		CompactRaidFrameContainer_AddFlaggedUnits(self);
		FlowContainer_AddLineBreak(self);
	end
	
	if ( self.groupMode == "discrete" ) then
		CompactRaidFrameContainer_AddGroups(self);
	elseif ( self.groupMode == "flush" ) then
		CompactRaidFrameContainer_AddPlayers(self);
	else
		error("Unknown group mode");
	end
	
	if ( self.displayPets ) then
		CompactRaidFrameContainer_AddPets(self);
	end
	
	FlowContainer_ResumeUpdates(self);
	
	CompactRaidFrameContainer_ReleaseAllReservedFrames(self);
end

do
	local usedGroups = {}; --Enclosure to make sure usedGroups isn't used anywhere else.
	function CompactRaidFrameContainer_AddGroups(self)
		RaidUtil_GetUsedGroups(usedGroups);
		
		local numGroups = 0;
		for groupNum, isUsed in ipairs(usedGroups) do
			if ( isUsed ) then
				numGroups = numGroups + 1;
				local groupFrame = CompactRaidGroup_GenerateForGroup(groupNum);
				groupFrame.unusedFunc = groupFrame.Hide;
				FlowContainer_AddObject(self, groupFrame);
				groupFrame:Show();
			end
		end
		FlowContainer_SetOrientation(self, "vertical")
	end
end


function CompactRaidFrameContainer_AddPlayers(self)
	--First, sort the players we're going to use
	assert(self.flowSortFunc);	--No sort function defined! Call CompactRaidFrameContainer_SetFlowSortFunction.
	assert(self.flowFilterFunc);	--No filter function defined! Call CompactRaidFrameContainer_SetFlowFilterFunction.
	
	table.sort(self.units, self.flowSortFunc);
	
	for i=1, #self.units do
		local unit = self.units[i];
		if ( self.flowFilterFunc(unit) ) then
			CompactRaidFrameContainer_AddUnitFrame(self, unit, "raid");
		end
	end
	
	FlowContainer_SetOrientation(self, "vertical")
end

function CompactRaidFrameContainer_AddPets(self)
	for i=1, MAX_RAID_MEMBERS do
		local unit = "raidpet"..i;
		if ( UnitExists(unit) ) then
			CompactRaidFrameContainer_AddUnitFrame(self, unit, "pet");
		end
	end
end

local flaggedRoles = { "MAINTANK", "MAINASSIST" };
function CompactRaidFrameContainer_AddFlaggedUnits(self)
	for roleIndex = 1, #flaggedRoles do
		local desiredRole = flaggedRoles[roleIndex]
		for i=1, MAX_RAID_MEMBERS do
			local unit = "raid"..i;
			local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
			if ( role == desiredRole ) then
				FlowContainer_BeginAtomicAdd(self);	--We want each unit to be right next to its target and target of target.
				
				CompactRaidFrameContainer_AddUnitFrame(self, unit, "flagged");
				
				--If we want to display the tank/assist target...
				local targetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."target", "target");
				CompactUnitFrame_SetUpdateAllOnUpdate(targetFrame, true);
				
				--Target of target?
				local targetOfTargetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."targettarget", "target");
				CompactUnitFrame_SetUpdateAllOnUpdate(targetOfTargetFrame, true);
				
				--Add some space before the next one.
				FlowContainer_AddSpacer(self, 36);
				
				FlowContainer_EndAtomicAdd(self);
			end
		end
	end		
end

--Utility Functions
function CompactRaidFrameContainer_AddUnitFrame(self, unit, frameType)
	local frame =CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType);
	CompactUnitFrame_SetUnit(frame, unit);
	FlowContainer_AddObject(self, frame);
	
	return frame;
end

local frameCreationSpecifiers = {
	raid = { mapping = UnitGUID, setUpFunc = DefaultCompactUnitFrameSetup },
	pet =  { setUpFunc = DefaultCompactMiniFrameSetup },
	flagged = { mapping = UnitGUID, setUpFunc = DefaultCompactUnitFrameSetup },
	target = { setUpFunc = DefaultCompactMiniFrameSetup },
}

local unitFramesCreated = 0;
function CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType)
	local info = frameCreationSpecifiers[frameType];
	assert(info);
	assert(info.setUpFunc);
	
	--Get the mapping for re-using frames
	local mapping;
	if ( info.mapping ) then
		mapping = info.mapping(unit);
	else
		mapping = unit;
	end
	
	local frame = CompactRaidFrameReservation_GetFrame(self.frameReservations[frameType], mapping);
	if ( not frame ) then
		unitFramesCreated = unitFramesCreated + 1;
		frame = CreateFrame("Button", "CompactRaidFrame"..unitFramesCreated, self, "CompactUnitFrameTemplate");
		CompactUnitFrame_SetUpFrame(frame, info.setUpFunc);
		frame.unusedFunc = self.unitFrameUnusedFunc;
		CompactRaidFrameReservation_RegisterReservation(self.frameReservations[frameType], frame, mapping);
	end
	frame.inUse = true;
	return frame;
end

function CompactRaidFrameContainer_ReleaseAllReservedFrames(self)
	for key, reservations in pairs(self.frameReservations) do
		CompactRaidFrameReservation_ReleaseUnusedReservations(reservations);
	end
end

function RaidUtil_GetUsedGroups(tab)	--Fills out the table with which groups have people.
	for i=1, MAX_RAID_GROUPS do
		tab[i] = false;
	end
	for i=1, GetNumRaidMembers() do
		local name, rank, subgroup = GetRaidRosterInfo(i);
		tab[subgroup] = true;
	end
	return tab;
end