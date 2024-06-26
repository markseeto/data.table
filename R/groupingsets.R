rollup = function(x, ...) {
  UseMethod("rollup")
}
rollup.data.table = function(x, j, by, .SDcols, id = FALSE, label = NULL, ...) {
  # input data type basic validation
  if (!is.data.table(x))
    stopf("Argument 'x' must be a data.table object")
  if (!is.character(by))
    stopf("Argument 'by' must be a character vector of column names used in grouping.")
  if (!is.logical(id))
    stopf("Argument 'id' must be a logical scalar.")
  # generate grouping sets for rollup
  sets = lapply(length(by):0L, function(i) by[0L:i])
  # redirect to workhorse function
  jj = substitute(j)
  groupingsets.data.table(x, by=by, sets=sets, .SDcols=.SDcols, id=id, jj=jj, label=label)
}

cube = function(x, ...) {
  UseMethod("cube")
}
cube.data.table = function(x, j, by, .SDcols, id = FALSE, label = NULL, ...) {
  # input data type basic validation
  if (!is.data.table(x))
    stopf("Argument 'x' must be a data.table object")
  if (!is.character(by))
    stopf("Argument 'by' must be a character vector of column names used in grouping.")
  if (!is.logical(id))
    stopf("Argument 'id' must be a logical scalar.")
  if (missing(j))
    stopf("Argument 'j' is required")
  # generate grouping sets for cube - power set: http://stackoverflow.com/a/32187892/2490497
  n = length(by)
  keepBool = sapply(2L^(seq_len(n)-1L), function(k) rep(c(FALSE, TRUE), times=k, each=((2L^n)/(2L*k))))
  sets = lapply((2L^n):1L, function(jj) by[keepBool[jj, ]])
  # redirect to workhorse function
  jj = substitute(j)
  groupingsets.data.table(x, by=by, sets=sets, .SDcols=.SDcols, id=id, jj=jj, label=label)
}

groupingsets = function(x, ...) {
  UseMethod("groupingsets")
}
groupingsets.data.table = function(x, j, by, sets, .SDcols, id = FALSE, jj, label = NULL, ...) {
  # input data type basic validation
  if (!is.data.table(x))
    stopf("Argument 'x' must be a data.table object")
  if (ncol(x) < 1L)
    stopf("Argument 'x' is a 0-column data.table; no measure to apply grouping over.")
  if (anyDuplicated(names(x)) > 0L)
    stopf("Input data.table must not contain duplicate column names.")
  if (!is.character(by))
    stopf("Argument 'by' must be a character vector of column names used in grouping.")
  if (anyDuplicated(by) > 0L)
    stopf("Argument 'by' must have unique column names for grouping.")
  if (!is.list(sets) || !all(vapply_1b(sets, is.character)))
    stopf("Argument 'sets' must be a list of character vectors.")
  if (!is.logical(id))
    stopf("Argument 'id' must be a logical scalar.")
  if (!(is.null(label) ||
        (is.atomic(label) && length(label) == 1L) ||
        (is.list(label) && all(vapply_1b(label, is.atomic)) &&
         all(vapply_1i(label, length) == 1L) && !is.null(names(label)))))
    stopf("Argument 'label', if not NULL, must be a scalar or a named list of scalars.")
  if (is.list(label) && !is.null(names(label)) && ("" %chin% names(label) || any(is.na(names(label)))))
    stopf("When argument 'label' is a list, all of the list elements must be named.")
  if (is.list(label) && anyDuplicated(names(label)))
    stopf("When argument 'label' is a list, the element names must not contain duplicates.")
  # logic constraints validation
  if (!all((sets.all.by <- unique(unlist(sets))) %chin% by))
    stopf("All columns used in 'sets' argument must be in 'by' too. Columns used in 'sets' but not present in 'by': %s", brackify(setdiff(sets.all.by, by)))
  if (id && "grouping" %chin% names(x))
    stopf("When using `id=TRUE` the 'x' data.table must not have a column named 'grouping'.")
  if (any(vapply_1i(sets, anyDuplicated)))  # anyDuplicated returns index of first duplicate, otherwise 0L
    stopf("Character vectors in 'sets' list must not have duplicated column names within a single grouping set.")
  if (length(sets) > 1L && (idx<-anyDuplicated(lapply(sets, sort))))
    warningf("'sets' contains a duplicate (i.e., equivalent up to sorting) element at index %d; as such, there will be duplicate rows in the output -- note that grouping by A,B and B,A will produce the same aggregations. Use `sets=unique(lapply(sets, sort))` to eliminate duplicates.", idx)
  if (is.list(label)) {
    other.allowed.names = c("character", "integer", "numeric", "factor", "Date", "IDate")
    allowed.label.list.names = c(by, vapply_1c(x[, by, with=FALSE], function(u) class(u)[1]),
                                 other.allowed.names)
    if (!all(names(label) %in% allowed.label.list.names))
      stopf(paste0("When argument 'label' is a list, all element names must be (1) in 'by', or (2) the first element of the class in the data.table 'x' of a variable in 'by', or (3) one of ",
                   paste(paste0("\"", other.allowed.names, "\""), collapse = ", "),
                   ". Element names not satisfying this condition: %s"),
            brackify(setdiff(names(label), allowed.label.list.names)))
    label.classes = lapply(label, class)
    label.names.in.by = intersect(names(label), by)
    label.names.not.in.by = setdiff(names(label), label.names.in.by)
    label.names.in.by.classes = label.classes[label.names.in.by]
    x.label.names.in.by.classes = lapply(x[, label.names.in.by, with=FALSE], class)
    label.names.in.by.classes.match = vapply_1b(label.names.in.by,
                                                function(u) identical(label.names.in.by.classes[[u]],
                                                                      x.label.names.in.by.classes[[u]]))
    label.names.not.in.by.classes1 = vapply_1c(label.classes[label.names.not.in.by], function(u) u[1])
    label.names.not.in.by.classes1.match = (label.names.not.in.by == label.names.not.in.by.classes1)
    if (!all(label.names.in.by.classes.match)) {
      label.names.in.by.classes.mismatch.info =
        paste0(label.names.in.by[!label.names.in.by.classes.match],
               " (label: ",
               vapply_1c(label.names.in.by.classes[!label.names.in.by.classes.match],
                         function(u) paste(u, collapse=", ")),
               "; data: ",
               vapply_1c(x.label.names.in.by.classes[!label.names.in.by.classes.match],
                         function(u) paste(u, collapse=", ")), ")")
      stopf("When argument 'label' is a list, the class of each 'label' element with name in 'by' must match the class of the corresponding column of the data.table 'x'. Class mismatch for: %s",
            brackify(label.names.in.by.classes.mismatch.info))
    }
    if (!all(label.names.not.in.by.classes1.match)) {
      label.names.not.in.by.classes1.mismatch.info =
        paste0("(label name: ",
               label.names.not.in.by[!label.names.not.in.by.classes1.match],
               "; label class[1]: ",
               label.names.not.in.by.classes1[!label.names.not.in.by.classes1.match], ")")
      stopf("When argument 'label' is a list, the name of each element of 'label' not in 'by' must match the first element of the class of the element value. Mismatches: %s",
            brackify(label.names.not.in.by.classes1.mismatch.info))
    }
  }
  # input arguments handling
  jj = if (!missing(jj)) jj else substitute(j)
  av = all.vars(jj, TRUE)
  if (":=" %chin% av)
    stopf("Expression passed to grouping sets function must not update by reference. Use ':=' on results of your grouping function.")
  if (missing(.SDcols))
    .SDcols = if (".SD" %chin% av) setdiff(names(x), by) else NULL
  if (length(names(by))) by = unname(by)
  # 0 rows template data.table to keep colorder and type
  empty = if (length(.SDcols)) x[0L, eval(jj), by, .SDcols=.SDcols] else x[0L, eval(jj), by]
  if (id && "grouping" %chin% names(empty)) # `j` could have been evaluated to `grouping` field
    stopf("When using `id=TRUE` the 'j' expression must not evaluate to a column named 'grouping'.")
  if (anyDuplicated(names(empty)) > 0L)
    stopf("There exists duplicated column names in the results, ensure the column passed/evaluated in `j` and those in `by` are not overlapping.")
  # adding grouping column to template - aggregation level identifier
  if (id) {
    set(empty, j = "grouping", value = integer())
    setcolorder(empty, c("grouping", by, setdiff(names(empty), c("grouping", by))))
  }
  # Define variables related to label
  if (!is.null(label)) {
    total.vars = intersect(by, unlist(lapply(sets, function(u) setdiff(by, u))))
    if (is.list(label)) {
      by.vars.not.in.label = setdiff(by, names(label))
      by.vars.not.in.label.class1 = vapply_1c(x[, by.vars.not.in.label, with=FALSE], function(u) class(u)[1])
      labels.by.vars.not.in.label =
        structure(label[by.vars.not.in.label.class1[by.vars.not.in.label.class1 %in% label.names.not.in.by]],
                  names = by.vars.not.in.label[by.vars.not.in.label.class1 %in% label.names.not.in.by])
      label.expanded = c(label[label.names.in.by], labels.by.vars.not.in.label)
      label.expanded = label.expanded[intersect(by, names(label.expanded))] # reorder
    } else {
      by.vars.matching.scalar.class1 = by[vapply_1c(x[, by, with=FALSE], function(u) class(u)[1]) ==
                                          class(label)[1]]
      label.expanded = structure(as.list(rep(label, length(by.vars.matching.scalar.class1))),
                                 names = by.vars.matching.scalar.class1)
    }
    label.use = label.expanded[intersect(total.vars, names(label.expanded))]
    label.expanded.value.in.x = vapply_1b(names(label.expanded), function(u) label.expanded[[u]] %in% x[[u]])
    if (any(label.expanded.value.in.x)) {
      label.value.in.x.info =
        paste0(names(label.expanded)[label.expanded.value.in.x], " (label: ",
               vapply_1c(label.expanded[label.expanded.value.in.x], as.character), ")")
      warningf("For the following variables, the 'label' value was already in the data: %s",
               brackify(label.value.in.x.info))
    }
  }
  # workaround for rbindlist fill=TRUE on integer64 #1459
  int64.cols = vapply_1b(empty, inherits, "integer64")
  int64.cols = names(int64.cols)[int64.cols]
  if (length(int64.cols) && !requireNamespace("bit64", quietly=TRUE))
    stopf("Using integer64 class columns require to have 'bit64' package installed.") # nocov
  int64.by.cols = intersect(int64.cols, by)
  # aggregate function called for each grouping set
  aggregate.set = function(by.set) {
    r = if (length(.SDcols)) x[, eval(jj), by.set, .SDcols=.SDcols] else x[, eval(jj), by.set]
    if (id) {
      # integer bit mask of aggregation levels: http://www.postgresql.org/docs/9.5/static/functions-aggregate.html#FUNCTIONS-GROUPING-TABLE
      # 3267: strtoi("", base = 2L) output apparently unstable across platforms
      i_str = paste(c("1", "0")[by %chin% by.set + 1L], collapse="")
      set(r, j = "grouping", value = if (nzchar(i_str)) strtoi(i_str, base=2L) else 0L)
    }
    if (length(int64.by.cols)) {
      # workaround for rbindlist fill=TRUE on integer64 #1459
      missing.int64.by.cols = setdiff(int64.by.cols, by.set)
      if (length(missing.int64.by.cols)) r[, (missing.int64.by.cols) := bit64::as.integer64(NA)]
    }
    if (!is.null(label))
      for (total.var in intersect(setdiff(by, by.set), names(label.use))) {
        r[, (total.var) := label.use[[total.var]]]
      }
    r
  }
  # actually processing everything here
  rbindlist(c(
    list(empty), # 0 rows template for colorder and type
    lapply(sets, aggregate.set) # all aggregations
  ), use.names=TRUE, fill=TRUE)
}
