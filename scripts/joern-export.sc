import java.nio.file.{Files, Paths}

@main def exec(cpgFile: String, outDir: String) = {
  val normalizedCpg = cpgFile.replace('\\', '/')
  val normalizedOut = outDir.replace('\\', '/')

  importCpg(normalizedCpg)

  val out = Paths.get(normalizedOut)
  Files.createDirectories(out)

  def esc(s: String): String = {
    Option(s).getOrElse("")
      .replace("\\", "\\\\")
      .replace("\"", "\\\"")
      .replace("\r", "\\r")
      .replace("\n", "\\n")
      .replace("\t", "\\t")
  }

  def q(s: String): String =
    "\"" + esc(s) + "\""

  def jsonArray(values: Seq[String]): String =
    values.mkString("[", ",", "]")

  def jsonInt(value: Option[Int]): String =
    value.map(_.toString).getOrElse("null")

  def displayLine(value: Option[Int]): String =
    value.map(_.toString).getOrElse("?")

  case class CallRow(
    caller: String,
    callerFile: String,
    code: String,
    directTarget: String,
    possibleTargets: List[String],
    internalTargets: List[String],
    line: Option[Int]
  )

  val types =
    cpg.typeDecl.internal.l
      .filter(t => t.name != "ANY" && t.filename != "<unknown>")
      .sortBy(_.fullName)

  val methods =
    cpg.method.internal.l
      .filter(m =>
        m.filename != "<unknown>" &&
        !m.name.startsWith("<operator>")
      )
      .sortBy(_.fullName)

  val internalMethodNames =
    methods.map(_.fullName).toSet

  val callRows =
    methods.flatMap { m =>
      m.start.call.l
        .filter(c => !c.name.startsWith("<operator>"))
        .map { c =>

          val possible =
            c.start.callee.fullName.l
              .distinct
              .sorted

          val internal =
            possible
              .filter(internalMethodNames.contains)
              .distinct
              .sorted

          CallRow(
            caller = m.fullName,
            callerFile = m.filename,
            code = c.code,
            directTarget = c.methodFullName,
            possibleTargets = possible,
            internalTargets = internal,
            line = c.lineNumber
          )
        }
    }

  val typesJson =
    types.map { t =>

      val bases =
        t.start.baseTypeDecl.fullName.l
          .distinct
          .sorted

      s"""    {
       |      "name": ${q(t.name)},
       |      "fullName": ${q(t.fullName)},
       |      "file": ${q(t.filename)},
       |      "inheritsFrom": ${jsonArray(bases.map(q))}
       |    }""".stripMargin
    }.mkString(",\n")

  val methodsJson =
    methods.map { m =>

      val owner =
        m.start.definingTypeDecl.fullName.headOption
          .getOrElse("")

      val conditions =
        m.start.controlStructure.code.l
          .distinct

      s"""    {
       |      "name": ${q(m.name)},
       |      "fullName": ${q(m.fullName)},
       |      "owner": ${q(owner)},
       |      "file": ${q(m.filename)},
       |      "line": ${jsonInt(m.lineNumber)},
       |      "conditions": ${jsonArray(conditions.map(q))}
       |    }""".stripMargin
    }.mkString(",\n")

  val callsJson =
    callRows.map { r =>

      s"""    {
       |      "caller": ${q(r.caller)},
       |      "file": ${q(r.callerFile)},
       |      "line": ${jsonInt(r.line)},
       |      "code": ${q(r.code)},
       |      "directTarget": ${q(r.directTarget)},
       |      "possibleTargets": ${jsonArray(r.possibleTargets.map(q))},
       |      "internalTargets": ${jsonArray(r.internalTargets.map(q))}
       |    }""".stripMargin
    }.mkString(",\n")

  val model =
    s"""{
       |  "schemaVersion": 1,
       |  "summary": {
       |    "types": ${types.size},
       |    "methods": ${methods.size},
       |    "calls": ${callRows.size}
       |  },
       |  "types": [
       |$typesJson
       |  ],
       |  "methods": [
       |$methodsJson
       |  ],
       |  "calls": [
       |$callsJson
       |  ]
       |}
       |""".stripMargin

  Files.writeString(
    out.resolve("static-model.json"),
    model
  )

  val report = new StringBuilder()

  report.append("STATIC APPLICATION MODEL\n")
  report.append("========================\n\n")

  report.append(s"Types:   ${types.size}\n")
  report.append(s"Methods: ${methods.size}\n")
  report.append(s"Calls:   ${callRows.size}\n\n")

  report.append("TYPES\n")
  report.append("-----\n")

  types.foreach { t =>

    val bases =
      t.start.baseTypeDecl.fullName.l
        .distinct
        .sorted

    report.append(s"\n${t.fullName}\n")
    report.append(s"  file: ${t.filename}\n")

    if (bases.nonEmpty) {
      report.append(
        s"  inherits/implements: ${bases.mkString(", ")}\n"
      )
    }
  }

  report.append("\n\nMETHODS AND CALLS\n")
  report.append("-----------------\n")

  methods.foreach { m =>

    report.append(s"\n${m.fullName}\n")
    report.append(
      s"  source: ${m.filename}:${displayLine(m.lineNumber)}\n"
    )

    val conditions =
      m.start.controlStructure.code.l.distinct

    conditions.foreach { condition =>
      report.append(s"  condition: $condition\n")
    }

    val calls =
      callRows.filter(_.caller == m.fullName)

    calls.foreach { c =>
      report.append(
        s"  -> ${c.directTarget} @ line ${displayLine(c.line)}\n"
      )

      report.append(
        s"     code: ${c.code}\n"
      )

      if (c.possibleTargets.nonEmpty) {
        report.append(
          s"     possible targets:\n"
        )

        c.possibleTargets.foreach { target =>
          report.append(
            s"       - $target\n"
          )
        }
      }
    }
  }

  Files.writeString(
    out.resolve("static-model.txt"),
    report.toString
  )

  def dotEsc(s: String): String =
    s.replace("\\", "\\\\")
      .replace("\"", "\\\"")

  val edges =
    callRows.flatMap { r =>

      val targets =
        if (r.internalTargets.nonEmpty) {
          r.internalTargets
        } else if (internalMethodNames.contains(r.directTarget)) {
          List(r.directTarget)
        } else {
          Nil
        }

      targets.map(target => (r.caller, target))
    }.distinct

  val dot = new StringBuilder()

  dot.append("digraph StaticCallGraph {\n")
  dot.append("  rankdir=LR;\n")
  dot.append("  node [shape=box];\n\n")

  methods.foreach { m =>
    dot.append(
      s"""  "${dotEsc(m.fullName)}";\n"""
    )
  }

  dot.append("\n")

  edges.foreach { case (caller, target) =>
    dot.append(
      s"""  "${dotEsc(caller)}" -> "${dotEsc(target)}";\n"""
    )
  }

  dot.append("}\n")

  Files.writeString(
    out.resolve("callgraph.dot"),
    dot.toString
  )

  println()
  println("Static model exported")
  println("---------------------")
  println(s"Types:   ${types.size}")
  println(s"Methods: ${methods.size}")
  println(s"Calls:   ${callRows.size}")
  println()
  println(out.resolve("static-model.json"))
  println(out.resolve("static-model.txt"))
  println(out.resolve("callgraph.dot"))
}
