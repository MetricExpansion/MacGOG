import Testing

@testable import MacGOG

@Suite struct HTMLTextTests {
    @Test func stripsTagsAndDecodesEntities() {
        let html =
            "<p>Fight <b>monsters</b> &amp; more.</p><ul><li>One</li><li>Two</li></ul><script>x()</script>"
        #expect(HTMLText.plainText(html) == "Fight monsters & more.\n\n• One\n• Two")
    }

    @Test func keepsLineBreaks() {
        #expect(HTMLText.plainText("A<br>B<br/>C") == "A\nB\nC")
    }

    @Test func sourceWhitespaceIsNotALineBreak() {
        let html =
            "<p>Gather\r\n   your party</p>\r\n<p><img src=\"x.jpg\"></p>\r\n<br>\r\n<p>Then  fight.</p>"
        #expect(HTMLText.plainText(html) == "Gather your party\n\nThen fight.")
    }
}
