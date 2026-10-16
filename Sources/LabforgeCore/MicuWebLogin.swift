public enum MicuWebLogin {
    // WebKit sets opener to the window itself after window.open(url, "_self").
    // Micu treats any opener as account binding instead of sign-in.
    public static let documentStartScript = """
        if (location.protocol === 'https:' &&
            ['www.micuapi.ai', 'micuapi.ai'].includes(location.hostname) &&
            ['/oauth/github', '/oauth/github/'].includes(location.pathname) &&
            window.opener === window) {
            window.opener = null;
        }
        """
}
