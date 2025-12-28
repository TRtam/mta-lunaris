function class(super)
	return setmetatable({
		destroy = function(object, ...)
			object:destructor(...)
			setmetatable(object, nil)
		end,
		prototype = setmetatable({
			constructor = function() end,
			destructor = function() end,
		}, {
			__index = function(_, key)
				if super then
					return super.prototype[key]
				end
			end,
		}),
	}, {
		__index = function(_, key)
			if super then
				return super[key]
			end
		end,
		__call = function(self, ...)
			local object = setmetatable({}, {
				__index = self.prototype,
			})
			local success, result = pcall(object.constructor, object, ...)
			if not success then
				error(result)
			end
			return object
		end,
	})
end
