Lunaris.Promise = class()

function Lunaris.Promise.deferred()
	local resolve, reject
	local promise = Lunaris.Promise(function(res, rej)
		resolve, reject = res, rej
	end)
	return promise, resolve, reject
end

function Lunaris.Promise.resolve(value)
	return Lunaris.Promise(function(resolve)
		resolve(value)
	end)
end

function Lunaris.Promise.reject(reason)
	return Lunaris.Promise(function(_, reject)
		reject(reason)
	end)
end

function Lunaris.Promise.all(promises)
	return Lunaris.Promise(function(resolve, reject)
		local results = {}
		local count = 0
		if #promises == 0 then
			resolve(results)
			return
		end
		for index, promise in ipairs(promises) do
			promise:next(function(value)
				results[index] = value
				count = count + 1
				if count == #promises then
					resolve(results)
				end
			end, reject)
		end
	end)
end

function Lunaris.Promise.prototype:constructor(executor)
	self.state = "pending"
	self.value = nil
	self.handlers = { fulfilled = {}, rejected = {}, finally = {} }
	local function resolve(value)
		if self.state ~= "pending" then
			return
		end
		if type(value) == "table" and value.next then
			value:next(resolve, reject)
			return
		end
		self.state = "fulfilled"
		self.value = value
		for _, handler in ipairs(self.handlers.fulfilled) do
			handler(value)
		end
		for _, handler in ipairs(self.handlers.finally) do
			handler()
		end
		self.handlers = {}
	end
	local function reject(reason)
		if self.state ~= "pending" then
			return
		end
		self.state = "rejected"
		self.value = reason
		for _, handler in ipairs(self.handlers.rejected) do
			handler(reason)
		end
		for _, handler in ipairs(self.handlers.finally) do
			handler()
		end
		self.handlers = {}
	end
	local success, result = pcall(executor, resolve, reject)
	if not success then
		reject(result)
	end
end

function Lunaris.Promise.prototype:next(on_fulfilled, on_rejected, on_finally)
	if type(on_fulfilled) ~= "function" then
		on_fulfilled = function()
			return true
		end
	end
	if type(on_rejected) ~= "function" then
		on_rejected = function()
			return false
		end
	end
	return Lunaris.Promise(function(resolve, reject)
		local function create_handler(handler)
			return function(value)
				local success, result = pcall(handler, value)
				if success then
					resolve(result)
				else
					reject(result)
				end
				if type(on_finally) == "function" then
					on_finally()
				end
			end
		end
		local handle_fulfilled = create_handler(on_fulfilled)
		local handle_rejected = create_handler(on_rejected)
		if self.state == "fulfilled" then
			handle_fulfilled(self.value)
		elseif self.state == "rejected" then
			handle_rejected(self.value)
		else
			table.insert(self.handlers.fulfilled, handle_fulfilled)
			table.insert(self.handlers.rejected, handle_rejected)
			if type(on_finally) == "function" then
				table.insert(self.handlers.finally, on_finally)
			end
		end
	end)
end

function Lunaris.Promise.prototype:catch(on_rejected)
	return self:next(nil, on_rejected)
end

function Lunaris.Promise.prototype:finally(on_finally)
	return self:next(nil, nil, on_finally)
end

function Lunaris.async(executor)
	return function(...)
		local task = coroutine.create(function(...)
			local returned = executor(...)
			return returned
		end)
		local promise, resolve, reject = Lunaris.Promise.deferred()
		local function step(...)
			local success, result = coroutine._resume(task, ...)
			if not success then
				reject(result)
			elseif coroutine.status(task) == "dead" then
				resolve(result)
			elseif type(result) == "table" and result.next then
				result:next(function(value)
					step(value)
				end, function(reason)
					step(reason)
				end)
			else
				step(result)
			end
		end
		step(...)
		return promise
	end
end

function Lunaris.await(promise)
	local result = coroutine.yield(promise)
	if type(result) == "table" and result.next then
		if result.state == "rejected" then
			error(result.reason)
		end
	end
	return result
end
