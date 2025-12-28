function Lunaris.eq(column, value)
	return { column = column, operator = "=", value = value }
end

function Lunaris.ne(column, value)
	return { column = column, operator = "!=", value = value }
end

function Lunaris.gt(column, value)
	return { column = column, operator = ">", value = value }
end

function Lunaris.gte(column, value)
	return { column = column, operator = ">=", value = value }
end

function Lunaris.lt(column, value)
	return { column = column, operator = "<", value = value }
end

function Lunaris.lte(column, value)
	return { column = column, operator = "<=", value = value }
end

function Lunaris.like(column, value)
	return { column = column, operator = "LIKE", value = value }
end

function Lunaris.in_array(column, values)
	return { column = column, operator = "IN", value = values }
end

function Lunaris.between(column, min, max)
	return { column = column, operator = "BETWEEN", value = { min, max } }
end

function Lunaris.is_null(column)
	return { column = column, operator = "IS NULL" }
end

function Lunaris.is_not_null(column)
	return { column = column, operator = "IS NOT NULL" }
end

function Lunaris.or_(...)
	return { junction = "OR", conditions = { ... } }
end

function Lunaris.and_(...)
	return { junction = "AND", conditions = { ... } }
end

function Lunaris.count(column)
	return { column = column, type = "COUNT", is_aggregation = true }
end

function Lunaris.sum(column)
	return { column = column, type = "SUM", is_aggregation = true }
end

function Lunaris.avg(column)
	return { column = column, type = "AVG", is_aggregation = true }
end

function Lunaris.min(column)
	return { column = column, type = "MIN", is_aggregation = true }
end

function Lunaris.max(column)
	return { column = column, type = "MAX", is_aggregation = true }
end

function Lunaris.sql(expression, ...)
	return { is_sql = true, expression = expression, params = { ... } }
end

function Lunaris.now()
	return Lunaris.sql("CURRENT_TIMESTAMP")
end

function Lunaris.placeholder(name)
	return { is_placeholder = true, name = name }
end

Lunaris.Query = class()

function Lunaris.Query.prototype:constructor(database)
	self.database = database
	self.parameters = {}
end

function Lunaris.Query.prototype:compile_condition(condition)
	local function prefix_column(column)
		if self._joins and #self._joins > 0 and column.table then
			return column.table._name .. "." .. column.name
		end
		return column.name
	end
	if condition.junction then
		local parts = {}
		for _, sub_condition in ipairs(condition.conditions) do
			table.insert(parts, "(" .. self:compile_condition(sub_condition) .. ")")
		end
		return table.concat(parts, " " .. condition.junction .. " ")
	end
	if condition.column.is_sql then
		for _, param in ipairs(condition.column.params) do
			if type(param) == "table" and param.is_placeholder then
				table.insert(self.parameters, param)
			else
				table.insert(self.parameters, param)
			end
		end
		return condition.column.expression
	end
	local query_string = prefix_column(condition.column) .. " " .. condition.operator
	if condition.operator == "IN" then
		local placeholders = {}
		for _, value_parameter in ipairs(condition.value) do
			table.insert(placeholders, "?")
			table.insert(self.parameters, value_parameter)
		end
		query_string = query_string .. " (" .. table.concat(placeholders, ", ") .. ")"
	elseif condition.operator == "BETWEEN" then
		query_string = query_string .. " ? AND ?"
		table.insert(self.parameters, condition.value[1])
		table.insert(self.parameters, condition.value[2])
	elseif condition.operator ~= "IS NULL" and condition.operator ~= "IS NOT NULL" then
		if type(condition.value) == "table" and condition.value.name and condition.value.table then
			query_string = query_string .. " " .. prefix_column(condition.value)
		else
			if type(condition.value) == "table" and condition.value.is_placeholder then
				query_string = query_string .. " ?"
				table.insert(self.parameters, condition.value)
			else
				query_string = query_string .. " ?"
				table.insert(self.parameters, condition.value)
			end
		end
	end
	return query_string
end

Lunaris.SelectQuery = class(Lunaris.Query)

function Lunaris.SelectQuery.prototype:constructor(database, columns)
	Lunaris.Query.prototype.constructor(self, database)
	self._columns = columns or "*"
	self._from = nil
	self._where = {}
	self._order_by = {}
	self._group_by = {}
	self._having = {}
	self._joins = {}
	self._with = {}
	self._limit = nil
	self._offset = nil
end

function Lunaris.SelectQuery.prototype:from(table_object)
	self._from = table_object
	return self
end

function Lunaris.SelectQuery.prototype:where(condition_object)
	table.insert(self._where, condition_object)
	return self
end

function Lunaris.SelectQuery.prototype:order_by(column, direction)
	table.insert(self._order_by, { column = column, direction = direction or "ASC" })
	return self
end

function Lunaris.SelectQuery.prototype:group_by(...)
	local columns = { ... }
	for _, column in ipairs(columns) do
		table.insert(self._group_by, column)
	end
	return self
end

function Lunaris.SelectQuery.prototype:having(condition_object)
	table.insert(self._having, condition_object)
	return self
end

function Lunaris.SelectQuery.prototype:left_join(table_object, condition)
	table.insert(self._joins, { type = "LEFT JOIN", table = table_object, condition = condition })
	return self
end

function Lunaris.SelectQuery.prototype:inner_join(table_object, condition)
	table.insert(self._joins, { type = "INNER JOIN", table = table_object, condition = condition })
	return self
end

function Lunaris.SelectQuery.prototype:right_join(table_object, condition)
	table.insert(self._joins, { type = "RIGHT JOIN", table = table_object, condition = condition })
	return self
end

function Lunaris.SelectQuery.prototype:limit(count)
	self._limit = count
	return self
end

function Lunaris.SelectQuery.prototype:offset(count)
	self._offset = count
	return self
end

function Lunaris.SelectQuery.prototype:with(relation_name, foreign_table, foreign_key, local_key)
	table.insert(self._with, {
		name = relation_name,
		foreign_table = foreign_table,
		foreign_key = foreign_key,
		local_key = local_key or "id",
	})
	return self
end

function Lunaris.SelectQuery.prototype:build_query_string()
	local function prefix_column(column)
		if #self._joins > 0 and column.table then
			return column.table._name .. "." .. column.name
		end
		return column.name
	end
	local query_string = "SELECT "
	if type(self._columns) == "table" then
		local column_names = {}
		-- Check if it's a map (aliasing) or array
		local is_map = false
		for k, v in pairs(self._columns) do
			if type(k) == "string" then
				is_map = true
				break
			end
		end
		if is_map then
			for alias, column_object in pairs(self._columns) do
				if column_object.is_sql then
					table.insert(column_names, column_object.expression .. " AS " .. alias)
				else
					table.insert(column_names, prefix_column(column_object) .. " AS " .. alias)
				end
			end
		else
			for _, column_object in ipairs(self._columns) do
				if column_object.is_sql then
					table.insert(column_names, column_object.expression)
				elseif column_object.is_aggregation then
					local inner = column_object.column == "*" and "*" or prefix_column(column_object.column)
					local alias = string.lower(
						column_object.type
							.. "_"
							.. (
								column_object.column == "*" and "all"
								or (column_object.column.table._name .. "_" .. column_object.column.name)
							)
					)
					table.insert(column_names, column_object.type .. "(" .. inner .. ") AS " .. alias)
				elseif #self._joins > 0 and column_object.table then
					table.insert(
						column_names,
						column_object.table._name
							.. "."
							.. column_object.name
							.. " AS "
							.. column_object.table._name
							.. "_"
							.. column_object.name
					)
				else
					table.insert(column_names, column_object.name)
				end
			end
		end
		query_string = query_string .. table.concat(column_names, ", ")
	else
		query_string = query_string .. self._columns
	end
	query_string = query_string .. " FROM " .. self._from._name
	if #self._joins > 0 then
		for _, join in ipairs(self._joins) do
			query_string = query_string
				.. " "
				.. join.type
				.. " "
				.. join.table._name
				.. " ON "
				.. self:compile_condition(join.condition)
		end
	end
	if #self._where > 0 then
		query_string = query_string .. " WHERE "
		local conditions = {}
		for _, condition in ipairs(self._where) do
			table.insert(conditions, self:compile_condition(condition))
		end
		query_string = query_string .. table.concat(conditions, " AND ")
	end
	if #self._group_by > 0 then
		local groups = {}
		for _, column_object in ipairs(self._group_by) do
			table.insert(groups, prefix_column(column_object))
		end
		query_string = query_string .. " GROUP BY " .. table.concat(groups, ", ")
	end

	if #self._having > 0 then
		query_string = query_string .. " HAVING "
		local conditions = {}
		for _, condition in ipairs(self._having) do
			table.insert(conditions, self:compile_condition(condition))
		end
		query_string = query_string .. table.concat(conditions, " AND ")
	end

	if #self._order_by > 0 then
		local orders = {}
		for _, order in ipairs(self._order_by) do
			table.insert(orders, prefix_column(order.column) .. " " .. string.upper(order.direction))
		end
		query_string = query_string .. " ORDER BY " .. table.concat(orders, ", ")
	end
	if self._limit then
		query_string = query_string .. " LIMIT " .. self._limit
	end
	if self._offset then
		query_string = query_string .. " OFFSET " .. self._offset
	end
	return query_string
end

function Lunaris.SelectQuery.prototype:execute()
	local query_string = self:build_query_string()
	local database = self.database
	local with_relations = self._with
	return self.database:query(query_string, unpack(self.parameters)):next(function(response)
		local results = response[1]
		if #with_relations == 0 or #results == 0 then
			return results
		end
		local relation_promises = {}
		for _, relation in ipairs(with_relations) do
			local ids_set = {}
			local ids_array = {}
			for _, row in ipairs(results) do
				local id = row[relation.local_key]
				if id and not ids_set[id] then
					ids_set[id] = true
					table.insert(ids_array, id)
				end
			end
			if #ids_array > 0 then
				local foreign_column = relation.foreign_table[relation.foreign_key]
				local relation_promise = database
					:select()
					:from(relation.foreign_table)
					:where(Lunaris.in_array(foreign_column, ids_array))
					:execute()
					:next(function(related_rows)
						for _, row in ipairs(results) do
							row[relation.name] = {}
							local row_id = tonumber(row[relation.local_key])
							for _, related in ipairs(related_rows) do
								local related_id = tonumber(related[relation.foreign_key])
								if related_id == row_id then
									table.insert(row[relation.name], related)
								end
							end
						end
					end)
				table.insert(relation_promises, relation_promise)
			end
		end
		return Lunaris.Promise.all(relation_promises):next(function()
			return results
		end)
	end)
end

Lunaris.InsertQuery = class(Lunaris.Query)

function Lunaris.InsertQuery.prototype:constructor(database, table_object)
	Lunaris.Query.prototype.constructor(self, database)
	self._table = table_object
	self._values = {}
	self._on_conflict = nil
	self._do_nothing = false
	self._returning = false
end

function Lunaris.InsertQuery.prototype:values(data)
	self._values = data
	return self
end

function Lunaris.InsertQuery.prototype:on_conflict_update(conflict_columns, update_columns)
	self._on_conflict = {
		conflict_columns = conflict_columns,
		update_columns = update_columns,
	}
	return self
end

function Lunaris.InsertQuery.prototype:on_conflict_do_nothing(conflict_columns)
	self._do_nothing = true
	self._on_conflict = { conflict_columns = conflict_columns or {} }
	return self
end

function Lunaris.InsertQuery.prototype:returning(columns)
	self._returning = columns or true
	return self
end

function Lunaris.InsertQuery.prototype:execute()
	for _, hook in ipairs(self._table._hooks.before_insert) do
		hook(self._values)
	end
	local is_batch = self._values[1] ~= nil and type(self._values[1]) == "table"
	local rows = is_batch and self._values or { self._values }
	local column_names = {}
	local all_placeholders = {}
	for _, row in ipairs(rows) do
		-- Apply Lua-based defaults
		for _, column in ipairs(self._table._columns) do
			if row[column.name] == nil and type(column._default) == "function" then
				row[column.name] = column._default()
			end
		end
		local row_placeholders = {}
		for column_name, value in pairs(row) do
			local actual_column = self._table[column_name]
			local name = actual_column and actual_column.name or column_name
			if #column_names < #row then
				table.insert(column_names, name)
			end
			table.insert(row_placeholders, "?")
			table.insert(self.parameters, value)
		end
		table.insert(all_placeholders, "(" .. table.concat(row_placeholders, ", ") .. ")")
	end
	if #column_names == 0 then
		for column_name, _ in pairs(rows[1]) do
			local actual_column = self._table[column_name]
			table.insert(column_names, actual_column and actual_column.name or column_name)
		end
	end
	local query_string = "INSERT INTO "
		.. self._table._name
		.. " ("
		.. table.concat(column_names, ", ")
		.. ") VALUES "
		.. table.concat(all_placeholders, ", ")
	if self._do_nothing then
		if self.database.driver == "sqlite" then
			local conflict_names = {}
			for _, col in ipairs(self._on_conflict.conflict_columns) do
				table.insert(conflict_names, type(col) == "table" and col.name or col)
			end
			if #conflict_names > 0 then
				query_string = query_string .. " ON CONFLICT (" .. table.concat(conflict_names, ", ") .. ") DO NOTHING"
			else
				query_string = query_string .. " ON CONFLICT DO NOTHING"
			end
		else
			query_string = query_string .. " ON DUPLICATE KEY UPDATE id = id"
		end
	elseif self._on_conflict and self._on_conflict.update_columns then
		local update_parts = {}
		for _, col in ipairs(self._on_conflict.update_columns) do
			local col_name = type(col) == "table" and col.name or col
			if self.database.driver == "sqlite" then
				table.insert(update_parts, col_name .. " = excluded." .. col_name)
			else
				table.insert(update_parts, col_name .. " = VALUES(" .. col_name .. ")")
			end
		end
		if self.database.driver == "sqlite" then
			local conflict_names = {}
			for _, col in ipairs(self._on_conflict.conflict_columns) do
				table.insert(conflict_names, type(col) == "table" and col.name or col)
			end
			query_string = query_string
				.. " ON CONFLICT ("
				.. table.concat(conflict_names, ", ")
				.. ") DO UPDATE SET "
				.. table.concat(update_parts, ", ")
		else
			query_string = query_string .. " ON DUPLICATE KEY UPDATE " .. table.concat(update_parts, ", ")
		end
	end
	if self._returning then
		if self.database.driver == "sqlite" then
			if self._returning == true then
				query_string = query_string .. " RETURNING *"
			else
				local return_cols = {}
				for _, col in ipairs(self._returning) do
					table.insert(return_cols, type(col) == "table" and col.name or col)
				end
				query_string = query_string .. " RETURNING " .. table.concat(return_cols, ", ")
			end
		end
	end
	local table_hooks = self._table._hooks
	return self.database:query(query_string, unpack(self.parameters)):next(function(result)
		for _, hook in ipairs(table_hooks.after_insert) do
			hook(result)
		end
		if self._returning and self.database.driver == "sqlite" then
			if not is_batch then
				return result[1][1]
			end
			return result[1]
		end
		return result
	end)
end

Lunaris.UpdateQuery = class(Lunaris.Query)

function Lunaris.UpdateQuery.prototype:constructor(database, table_object)
	Lunaris.Query.prototype.constructor(self, database)
	self._table = table_object
	self._set = {}
	self._where = {}
	self._returning = false
end

function Lunaris.UpdateQuery.prototype:set(data)
	self._set = data
	return self
end

function Lunaris.UpdateQuery.prototype:where(condition_object)
	table.insert(self._where, condition_object)
	return self
end

function Lunaris.UpdateQuery.prototype:returning(columns)
	self._returning = columns or true
	return self
end

function Lunaris.UpdateQuery.prototype:execute()
	for _, hook in ipairs(self._table._hooks.before_update) do
		hook(self._set)
	end
	local set_clauses = {}
	for column_name, value in pairs(self._set) do
		local actual_column = self._table[column_name]
		local name = actual_column and actual_column.name or column_name
		table.insert(set_clauses, name .. " = ?")
		table.insert(self.parameters, value)
	end
	local query_string = "UPDATE " .. self._table._name .. " SET " .. table.concat(set_clauses, ", ")
	if #self._where > 0 then
		query_string = query_string .. " WHERE "
		local conditions = {}
		for _, condition in ipairs(self._where) do
			table.insert(conditions, self:compile_condition(condition))
		end
		query_string = query_string .. table.concat(conditions, " AND ")
	end
	if self._returning and self.database.driver == "sqlite" then
		if self._returning == true then
			query_string = query_string .. " RETURNING *"
		else
			local return_cols = {}
			for _, col in ipairs(self._returning) do
				table.insert(return_cols, type(col) == "table" and col.name or col)
			end
			query_string = query_string .. " RETURNING " .. table.concat(return_cols, ", ")
		end
	end
	local table_hooks = self._table._hooks
	return self.database:query(query_string, unpack(self.parameters)):next(function(result)
		for _, hook in ipairs(table_hooks.after_update) do
			hook(result)
		end
		if self._returning and self.database.driver == "sqlite" then
			return result[1]
		end
		return result
	end)
end

Lunaris.DeleteQuery = class(Lunaris.Query)

function Lunaris.DeleteQuery.prototype:constructor(database, table_object)
	Lunaris.Query.prototype.constructor(self, database)
	self._table = table_object
	self._where = {}
	self._returning = false
end

function Lunaris.DeleteQuery.prototype:where(condition_object)
	table.insert(self._where, condition_object)
	return self
end

function Lunaris.DeleteQuery.prototype:returning(columns)
	self._returning = columns or true
	return self
end

function Lunaris.DeleteQuery.prototype:execute()
	for _, hook in ipairs(self._table._hooks.before_delete) do
		hook(self._where)
	end
	local query_string = "DELETE FROM " .. self._table._name
	if #self._where > 0 then
		query_string = query_string .. " WHERE "
		local conditions = {}
		for _, condition in ipairs(self._where) do
			table.insert(conditions, self:compile_condition(condition))
		end
		query_string = query_string .. table.concat(conditions, " AND ")
	end
	if self._returning and self.database.driver == "sqlite" then
		if self._returning == true then
			query_string = query_string .. " RETURNING *"
		else
			local return_cols = {}
			for _, col in ipairs(self._returning) do
				table.insert(return_cols, type(col) == "table" and col.name or col)
			end
			query_string = query_string .. " RETURNING " .. table.concat(return_cols, ", ")
		end
	end
	local table_hooks = self._table._hooks
	return self.database:query(query_string, unpack(self.parameters)):next(function(result)
		for _, hook in ipairs(table_hooks.after_delete) do
			hook(result)
		end
		if self._returning and self.database.driver == "sqlite" then
			return result[1]
		end
		return result
	end)
end

Lunaris.PreparedQuery = class()

function Lunaris.PreparedQuery.prototype:constructor(database, query_template, placeholder_names)
	self.database = database
	self.query_template = query_template
	self.placeholder_names = placeholder_names
end

function Lunaris.PreparedQuery.prototype:execute(params)
	local query_string = self.query_template
	local query_params = {}
	for _, name in ipairs(self.placeholder_names) do
		table.insert(query_params, params[name])
	end
	return self.database:query(query_string, unpack(query_params))
end

function Lunaris.SelectQuery.prototype:prepare()
	local query_string = self:build_query_string()
	local placeholder_names = {}
	for i, param in ipairs(self.parameters) do
		if type(param) == "table" and param.is_placeholder then
			table.insert(placeholder_names, param.name)
		end
	end
	return Lunaris.PreparedQuery(self.database, query_string, placeholder_names)
end
