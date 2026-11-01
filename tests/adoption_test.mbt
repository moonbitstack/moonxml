/// The canonical misnesting cases from the WHATWG adoption agency algorithm.

test "adoption: formatting ends before a nested formatting element" {
  assert_eq(@html.loads("<p>1<b>2<i>3</b>4</i>5</p>").css("body").html(), "<p>1<b>2<i>3</i></b><i>4</i>5</p>")
}

test "adoption: block inside formatting" {
  assert_eq(@html.loads("<b>1<p>2</b>3</p>").css("body").html(), "<b>1</b><p><b>2</b>3</p>")
}

test "adoption: crossing formatting tags" {
  assert_eq(@html.loads("<b><i></b></i>").css("body").html(), "<b><i></i></b>")
  assert_eq(@html.loads("<a><b></a></b>").css("body").html(), "<a><b></b></a>")
}

test "adoption: reopening after the block" {
  assert_eq(@html.loads("<p><b>1<i>2</b>3</i></p>").css("body").html(), "<p><b>1<i>2</i></b><i>3</i></p>")
}
