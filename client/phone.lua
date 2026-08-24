-- Client exports for phone apps, see docs/phone-integrations.md.
-- Everything is validated server-side, these are convenience wrappers only.

exports('GetMyHomes', function()
    return lib.callback.await('qbx_properties:callback:phoneHomes', false) or {}
end)

exports('GetHomeKeyholders', function(propertyId)
    return lib.callback.await('qbx_properties:callback:phoneKeyholders', false, propertyId)
end)

exports('AddHomeKeyholder', function(propertyId, targetServerId)
    return lib.callback.await('qbx_properties:callback:phoneAddKeyholder', false, propertyId, targetServerId) == true
end)

exports('RemoveHomeKeyholder', function(propertyId, citizenid)
    return lib.callback.await('qbx_properties:callback:phoneRemoveKeyholder', false, propertyId, citizenid) == true
end)

---@return boolean? locked the new state, nil when the property has no toggleable doors or access was denied
exports('SetHomeLocked', function(propertyId, locked)
    return lib.callback.await('qbx_properties:callback:phoneSetLocked', false, propertyId, locked)
end)
