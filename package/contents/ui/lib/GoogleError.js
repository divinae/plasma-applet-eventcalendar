.pragma library

// Google's error body { error: { code, message, errors: [{ reason, domain, message }] } } of a
// failed request, else null. err, data: as Requests.getJSON gives them. Google's body is err when
// a 2xx answer carried one (GoogleCalendarManager.googleRequest), else the text of an HTTP error
// in data (or data already parsed).
// https://developers.google.com/calendar/v3/errors
function googleErrorBody(err, data) {
	if (err && err.error) {
		return err
	}
	var body = data
	if (typeof body === 'string') {
		try {
			body = JSON.parse(body)
		} catch (e) {
			return null // Not JSON, eg: an HTML error page
		}
	}
	return body && body.error ? body : null
}
