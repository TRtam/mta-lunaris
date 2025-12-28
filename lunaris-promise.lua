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

function Lunaris.Promise.timeout(executor, interval, reason)
	local promise, resolve, reject = Lunaris.Promise.deferred()
	setTimer(function()
		reject(reason or "timeout")
	end, interval, 1)
	local success, result = pcall(executor, resolve, reject)
	if not success then
		reject(result)
	end
	return promise
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
	local success, result = pcall(executor, function(value)
		self:resolve(value)
	end, function(reason)
		self:reject(reason)
	end)
	if not success then
		self:reject(result)
	end
end

function Lunaris.Promise.prototype:resolve(value)
	if self.state ~= "pending" then
		return
	end
	if type(value) == "table" and value.next then
		value:next(function(value)
			self:resolve(value)
		end, function(reason)
			self:reject(reason)
		end)
	else
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
end

function Lunaris.Promise.prototype:reject(reason)
	if self.state ~= "pending" then
		return
	end
	if type(reason) == "table" and reason.next then
		reason:next(function(value)
			self:resolve(value)
		end, function(reason)
			self:reject(reason)
		end)
	else
		self.state = "rejected"
		self.reason = reason
		for _, handler in ipairs(self.handlers.rejected) do
			handler(reason)
		end
		for _, handler in ipairs(self.handlers.finally) do
			handler()
		end
		self.handlers = {}
	end
end

function Lunaris.Promise.prototype:next(on_fulfilled, on_rejected, on_finally)
	if type(on_fulfilled) ~= "function" then
		on_fulfilled = function(value)
			return value
		end
	end
	if type(on_rejected) ~= "function" then
		on_rejected = function(reason)
			error(reason)
		end
	end
	local promise, resolve, reject = Lunaris.Promise.deferred()
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
		handle_rejected(self.reason)
	else
		table.insert(self.handlers.fulfilled, handle_fulfilled)
		table.insert(self.handlers.rejected, handle_rejected)
		if type(on_finally) == "function" then
			table.insert(self.handlers.finally, on_finally)
		end
	end
	return promise
end

function Lunaris.Promise.prototype:catch(on_rejected)
	return self:next(nil, on_rejected)
end

function Lunaris.Promise.prototype:finally(on_finally)
	return self:next(nil, nil, on_finally)
end

local TASKS_PROMISES = {}

function Lunaris.async(executor)
	return function(...)
		local task = coroutine.create(function(...)
			local returned = executor(...)
			TASKS_PROMISES[coroutine.running()] = nil
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
		TASKS_PROMISES[task] = promise
		step(...)
		return promise
	end
end

function Lunaris.throw(e)
	local promise = TASKS_PROMISES[coroutine.running()]
	if promise then
		promise:reject(e)
	else
		error(tostring(e))
	end
end

function Lunaris.await(x)
	if not coroutine.running() then
		return x
	end
	if type(x) == "table" and x.next then
		local result = coroutine.yield(x)
		if x.state == "rejected" then
			Lunaris.throw(x.reason)
		end
		return result
	end
	return x
end

function Lunaris.try(executor, catch, finally)
	if coroutine.running() then
		local promise = Lunaris.async(executor)():catch(Lunaris.async(catch))
		if type(finally) == "function" then
			finally = Lunaris.async(finally)
			promise = promise:next(finally, finally)
		end
		return Lunaris.await(promise)
	else
		local success, result = pcall(executor)
		if not success then
			_, result = pcall(catch, result)
		end
		if type(finally) == "function" then
			local finally_success, finally_result = pcall(finally)
			if not finally_success then
				result = finally_result
			end
		end
		return result
	end
end
