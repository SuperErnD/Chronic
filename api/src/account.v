module main

import veb
import veb.auth
import db.tables
import superernd.jwt
import net.http
import json

// here we define a account methods (e.g. change password, login, logout, register, deletion of account, account status)

enum UserStatus {
	good    = 0 // User in good state (no currently bans, mutes, etc.)
	muted   = 1 // User is just muted, nothing else
	limited = 2 // User is limited, for example user cant see other users, and other users cant see the user
	banned  = 3 // User is banned, user cant enter the game at all
}

struct UserClaims {
	id int
}

@[post]
pub fn (mut app App) register(mut ctx Context) veb.Result {
	name := ctx.query['name'] or {
		ctx.res.set_status(.bad_request)
		return ctx.json({
			'error': 'Username is not provided.'
		})
	}

	password := ctx.query['password'] or {
		ctx.res.set_status(.bad_request)
		return ctx.json({
			'error': 'Password is not provided.'
		})
	}

	country := (json.decode(IpApiResponse, http.get_text('http://ip-api.com/json/${ctx.ip()}?fields=countryCode')) or {}).country

	salt := auth.generate_salt()
	new_user := tables.User{
		name: name
		password_hash: auth.hash_password_with_salt(password, salt)
		country: country
		salt: salt
	}
	sql app.db {
		insert new_user into tables.User
	} or {
		println(err)
		ctx.res.set_status(.internal_server_error)
		return ctx.json({
			'error': 'Something went wrong while creating account.'
		})
	}

	if x := app.find_user_by_name(name) {
		alg := jwt.new_algorithm(jwt.AlgorithmType.hs256)
		token := jwt.encode[UserClaims](UserClaims{
			id: x.id
		}, alg, app.salt, 168 * 60 * 60) or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json({
				'error': 'Something went wrong while creating account.'
			})
		}
		return ctx.json({
			'token': token
		})
	}
	ctx.res.set_status(.internal_server_error)
	return ctx.json({
		'error': 'Something went wrong. Account is seems not registered, just try again register.'
	})
}

@[post]
pub fn (mut app App) login(mut ctx Context) veb.Result {
	name := ctx.query['name'] or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Bad credentials.'
		})
	}

	password := ctx.query['password'] or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Bad credentials.'
		})
	}

	user := app.find_user_by_name(name) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Bad credentials.'
		})
	}

	if !auth.compare_password_with_hash(password, user.salt, user.password_hash) {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Bad credentials.'
		})
	}

	alg := jwt.new_algorithm(jwt.AlgorithmType.hs256)
	token := jwt.encode[UserClaims](UserClaims{
		id: user.id
	}, alg, app.salt, 168 * 60 * 60) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json({
			'error': 'Something went wrong while creating token!'
		})
	}

	return ctx.json({
		'token': token
	})
}

pub fn (mut app App) me(mut ctx Context) veb.Result {
	user := app.auth_user(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Token not provided/invalid'
		})
	}

	return ctx.json({
		'name':    user.name
		'bio':     user.bio
		'avatar':  user.avatar
		'banner':  user.banner
		'country': user.country
		'id':      user.id.str()
	})
}

@[patch]
pub fn (mut app App) modify(mut ctx Context) veb.Result {
	user := app.auth_user(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Token not provided/invalid'
		})
	}

	modificated := json.decode(AccountModificationRequest, ctx.res.body) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json({
			'error': 'Failed to parse body'
		})
	}

	if modificated.key == 'bio' {
		sql app.db {
			update tables.User set bio = modificated.value where id == user.id
		} or { println(err) }
	} else {
		ctx.res.set_status(.bad_request)
		return ctx.json({
			'error': 'Bad Request: No such modification'
		})
	}

	ctx.res.set_status(.no_content)
	return ctx.text('')
}
