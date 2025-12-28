Lunaris.Column = class()

function Lunaris.Column.prototype:constructor(name, data_type, config)
	self.name = name
	self.data_type = data_type
	self.config = config or {}
	self._primary_key = false
	self._not_null = false
	self._unique = false
	self._default = nil
	self._references = nil
	self.table = nil
end

function Lunaris.Column.prototype:primary_key()
	self._primary_key = true
	return self
end

function Lunaris.Column.prototype:not_null()
	self._not_null = true
	return self
end

function Lunaris.Column.prototype:unique()
	self._unique = true
	return self
end

function Lunaris.Column.prototype:default(value)
	self._default = value
	return self
end

function Lunaris.Column.prototype:references(foreign_table, foreign_column, actions)
	self._references = {
		table = foreign_table,
		column = foreign_column or "id",
		on_delete = actions and actions.on_delete or nil,
		on_update = actions and actions.on_update or nil,
	}
	return self
end

function Lunaris.id(name)
	return Lunaris.serial(name or "id")
end

function Lunaris.integer(name)
	return Lunaris.Column(name, "INTEGER")
end

function Lunaris.tinyint(name)
	return Lunaris.Column(name, "TINYINT")
end

function Lunaris.smallint(name)
	return Lunaris.Column(name, "SMALLINT")
end

function Lunaris.bigint(name)
	return Lunaris.Column(name, "BIGINT")
end

function Lunaris.varchar(name, config)
	return Lunaris.Column(name, "VARCHAR", config)
end

function Lunaris.uuid(name)
	return Lunaris.varchar(name or "uuid", { length = 36 })
end

function Lunaris.text(name)
	return Lunaris.Column(name, "TEXT")
end

function Lunaris.boolean(name)
	return Lunaris.Column(name, "BOOLEAN")
end

function Lunaris.serial(name)
	return Lunaris.Column(name, "SERIAL"):primary_key()
end

function Lunaris.timestamp(name)
	return Lunaris.Column(name, "TIMESTAMP")
end

Lunaris.Table = class()

function Lunaris.Table.prototype:constructor(name, columns, configuration)
	self._name = name
	self._configuration = configuration or { timestamps = true }
	self._columns = columns
	self._hooks = {
		before_insert = {},
		after_insert = {},
		before_update = {},
		after_update = {},
		before_delete = {},
		after_delete = {},
	}
	if self._configuration.timestamps then
		table.insert(
			self._columns,
			Lunaris.timestamp("created_at"):not_null():default(Lunaris.sql("CURRENT_TIMESTAMP"))
		)
		table.insert(
			self._columns,
			Lunaris.timestamp("updated_at"):not_null():default(Lunaris.sql("CURRENT_TIMESTAMP"))
		)
	end
	for _, column in ipairs(self._columns) do
		column.table = self
		self[column.name] = column
	end
end

function Lunaris.Table.prototype:before_insert(callback)
	table.insert(self._hooks.before_insert, callback)
	return self
end

function Lunaris.Table.prototype:after_insert(callback)
	table.insert(self._hooks.after_insert, callback)
	return self
end

function Lunaris.Table.prototype:before_update(callback)
	table.insert(self._hooks.before_update, callback)
	return self
end

function Lunaris.Table.prototype:after_update(callback)
	table.insert(self._hooks.after_update, callback)
	return self
end

function Lunaris.Table.prototype:before_delete(callback)
	table.insert(self._hooks.before_delete, callback)
	return self
end

function Lunaris.Table.prototype:after_delete(callback)
	table.insert(self._hooks.after_delete, callback)
	return self
end

function Lunaris.Column.prototype:to_sql(driver)
	local sql_parts = { self.name }
	local current_data_type = self.data_type
	if current_data_type == "SERIAL" then
		if driver == "mysql" then
			current_data_type = "INT AUTO_INCREMENT"
		elseif driver == "sqlite" then
			current_data_type = "INTEGER"
		end
	end
	if self.data_type == "VARCHAR" and self.config.length then
		current_data_type = "VARCHAR(" .. self.config.length .. ")"
	end
	table.insert(sql_parts, current_data_type)
	if self._primary_key then
		if self.data_type == "SERIAL" and driver == "sqlite" then
			table.insert(sql_parts, "PRIMARY KEY AUTOINCREMENT")
		else
			table.insert(sql_parts, "PRIMARY KEY")
		end
	end
	if self._not_null then
		table.insert(sql_parts, "NOT NULL")
	end
	if self._unique then
		table.insert(sql_parts, "UNIQUE")
	end
	if self._default ~= nil then
		local default_expression = self._default
		local should_add_default = true
		if type(default_expression) == "table" and default_expression.is_sql then
			default_expression = default_expression.expression
		elseif type(default_expression) == "function" then
			should_add_default = false
		elseif type(default_expression) == "string" then
			default_expression = "'" .. default_expression .. "'"
		elseif type(default_expression) == "boolean" then
			default_expression = default_expression and "1" or "0"
		end
		if should_add_default then
			table.insert(sql_parts, "DEFAULT " .. default_expression)
		end
	end
	return table.concat(sql_parts, " ")
end

function Lunaris.Table.prototype:to_sql(driver)
	local column_sqls = {}
	local foreign_keys = {}
	for _, column_object in ipairs(self._columns) do
		table.insert(column_sqls, column_object:to_sql(driver))
		if column_object._references then
			local ref = column_object._references
			local fk_sql = "FOREIGN KEY ("
				.. column_object.name
				.. ") REFERENCES "
				.. ref.table._name
				.. "("
				.. ref.column
				.. ")"
			if ref.on_delete then
				fk_sql = fk_sql .. " ON DELETE " .. ref.on_delete
			end
			if ref.on_update then
				fk_sql = fk_sql .. " ON UPDATE " .. ref.on_update
			end
			table.insert(foreign_keys, fk_sql)
		end
	end
	for _, fk in ipairs(foreign_keys) do
		table.insert(column_sqls, fk)
	end
	return "CREATE TABLE IF NOT EXISTS " .. self._name .. " (" .. table.concat(column_sqls, ", ") .. ")"
end
