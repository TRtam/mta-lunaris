Lunaris = class()

function Lunaris.prototype:constructor(driver, config)
	self.driver = driver
	self.debug = config.debug or false
	self.timeout_ms = config.timeout
	local options_parts = {}
	local shared_options = {
		"share",
		"batch",
		"autoreconnect",
		"log",
		"tag",
		"suppress",
		"multi_statements",
		"queue",
		"use_ssl",
		"get_server_public_key",
	}
	for _, key in ipairs(shared_options) do
		if config[key] ~= nil then
			table.insert(options_parts, key .. "=" .. tostring(config[key]))
		end
	end
	if config.options then
		table.insert(options_parts, config.options)
	end
	local options_string = table.concat(options_parts, ";")
	if driver == "mysql" then
		local connection_parts = {}
		if config.dbname then
			table.insert(connection_parts, "dbname=" .. config.dbname)
		end
		if config.host then
			table.insert(connection_parts, "host=" .. config.host)
		end
		if config.port then
			table.insert(connection_parts, "port=" .. config.port)
		end
		if config.unix_socket then
			table.insert(connection_parts, "unix_socket=" .. config.unix_socket)
		end
		if config.charset then
			table.insert(connection_parts, "charset=" .. config.charset)
		end
		self.connection = dbConnect(
			driver,
			table.concat(connection_parts, ";"),
			config.username or "",
			config.password or "",
			options_string
		)
	elseif driver == "sqlite" then
		self.connection = dbConnect(driver, config.filepath, "", "", options_string)
		if self.connection then
			dbExec(self.connection, "PRAGMA foreign_keys = ON")
		end
	end
	if not self.connection then
		error("Failed to connect to database (" .. driver .. ")")
	end
end

function Lunaris.prototype:query(query_string, ...)
	local query_arguments = { ... }
	return Lunaris.Promise(function(resolve, reject)
		local sql_string = dbPrepareString(self.connection, query_string, unpack(query_arguments))
		if self.debug then
			print("[Lunaris] " .. sql_string)
		end
		local query_handle
		local timer
		query_handle = dbQuery(function(handle)
			if isTimer(timer) then
				killTimer(timer)
			end
			local result = { dbPoll(handle, 0) }
			if result[1] == nil then
				reject("Query failed result nil")
			elseif result[1] == false then
				reject(result[2])
			else
				resolve(result)
			end
		end, self.connection, sql_string)

		local timeout = self.timeout_ms or 10000
		timer = setTimer(function()
			if query_handle then
				dbFree(query_handle)
			end
			reject("Query timed out after " .. timeout .. "ms")
		end, timeout, 1)
	end)
end

function Lunaris.prototype:select(columns)
	return Lunaris.SelectQuery(self, columns)
end

function Lunaris.prototype:insert(table)
	return Lunaris.InsertQuery(self, table)
end

function Lunaris.prototype:update(table)
	return Lunaris.UpdateQuery(self, table)
end

function Lunaris.prototype:delete(table)
	return Lunaris.DeleteQuery(self, table)
end

function Lunaris.prototype:sync(schema_tables, options)
	options = options or {}
	local function create_tables()
		local creation_promises = {}
		for _, table_object in ipairs(schema_tables) do
			table.insert(creation_promises, self:query(table_object:to_sql(self.driver)))
		end
		return Lunaris.Promise.all(creation_promises)
	end
	if options.force then
		local drop_promises = {}
		for _, table_object in ipairs(schema_tables) do
			table.insert(drop_promises, self:query("DROP TABLE IF EXISTS " .. table_object._name))
		end
		return Lunaris.Promise.all(drop_promises):next(create_tables)
	end
	return create_tables()
end

function Lunaris.prototype:begin_transaction()
	local statement = self.driver == "mysql" and "START TRANSACTION" or "BEGIN TRANSACTION"
	return self:query(statement)
end

function Lunaris.prototype:commit()
	return self:query("COMMIT")
end

function Lunaris.prototype:rollback()
	return self:query("ROLLBACK")
end

function Lunaris.prototype:transaction(callback)
	return self:begin_transaction()
		:next(function()
			return callback()
		end)
		:next(function(result)
			return self:commit():next(function()
				return result
			end)
		end)
		:catch(function(error_message)
			return self:rollback():next(function()
				error(error_message)
			end)
		end)
end
