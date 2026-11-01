pub fn sample() -> @moonxml.Document {
  @html.loads("<div id=\"a\"><ul><li>1</li><li>2</li><li class=\"last\">3</li></ul><p>x</p></div>")
}
