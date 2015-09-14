def reload():
	__salt__['cmd.run']('consul reload')