#include "Python.h"

/* --------------------------------------------------------- */
/* C implementation of _deepcopy_list                        */
/* --------------------------------------------------------- */
static PyObject *
deepcopy_list_c(PyObject *self, PyObject *args)
{
    PyObject *x;       /* list to copy */
    PyObject *memo;    /* dict memo    */
    PyObject *deepcopy_func; /* Python's deepcopy callable */

    if (!PyArg_ParseTuple(args, "OOO", &x, &memo, &deepcopy_func))
        return NULL;

    if (!PyList_CheckExact(x)) {
        PyErr_SetString(PyExc_TypeError, "expected list");
        return NULL;
    }

    Py_ssize_t n = PyList_GET_SIZE(x);
    PyObject *y = PyList_New(n);
    if (y == NULL) {
        return NULL;
    }

    /* Add y to memo early */
    PyObject *key = PyLong_FromVoidPtr(x);
    if (key == NULL) {
        Py_DECREF(y);
        return NULL;
    }
    if (PyDict_SetItem(memo, key, y) < 0) {
        Py_DECREF(key);
        Py_DECREF(y);
        return NULL;
    }
    Py_DECREF(key);

    for (Py_ssize_t i = 0; i < n; i++) {
        PyObject *item = PyList_GET_ITEM(x, i);
        PyObject *new_item = PyObject_CallFunctionObjArgs(
            deepcopy_func, item, memo, NULL);
        if (new_item == NULL) {
            Py_DECREF(y);
            return NULL;
        }
        PyList_SET_ITEM(y, i, new_item);  /* steals reference */
    }

    return y;
}

/* --------------------------------------------------------- */
/* C implementation of _deepcopy_dict                        */
/* --------------------------------------------------------- */
static PyObject *
deepcopy_dict_c(PyObject *self, PyObject *args)
{
    PyObject *x;
    PyObject *memo;
    PyObject *deepcopy_func;

    if (!PyArg_ParseTuple(args, "OOO", &x, &memo, &deepcopy_func))
        return NULL;

    if (!PyDict_CheckExact(x)) {
        PyErr_SetString(PyExc_TypeError, "expected dict");
        return NULL;
    }

    PyObject *y = PyDict_New();
    if (y == NULL) {
        return NULL;
    }

    PyObject *key_memo = PyLong_FromVoidPtr(x);
    if (key_memo == NULL) {
        Py_DECREF(y);
        return NULL;
    }
    if (PyDict_SetItem(memo, key_memo, y) < 0) {
        Py_DECREF(key_memo);
        Py_DECREF(y);
        return NULL;
    }
    Py_DECREF(key_memo);

    PyObject *key, *value;
    Py_ssize_t pos = 0;
    while (PyDict_Next(x, &pos, &key, &value)) {
        PyObject *new_key = PyObject_CallFunctionObjArgs(
            deepcopy_func, key, memo, NULL);
        if (new_key == NULL) {
            Py_DECREF(y);
            return NULL;
        }
        PyObject *new_value = PyObject_CallFunctionObjArgs(
            deepcopy_func, value, memo, NULL);
        if (new_value == NULL) {
            Py_DECREF(new_key);
            Py_DECREF(y);
            return NULL;
        }
        if (PyDict_SetItem(y, new_key, new_value) < 0) {
            Py_DECREF(new_key);
            Py_DECREF(new_value);
            Py_DECREF(y);
            return NULL;
        }
        Py_DECREF(new_key);
        Py_DECREF(new_value);
    }

    return y;
}

/* --------------------------------------------------------- */
/* C implementation of _deepcopy_tuple                       */
/* --------------------------------------------------------- */
static PyObject *
deepcopy_tuple_c(PyObject *self, PyObject *args)
{
    PyObject *x;
    PyObject *memo;
    PyObject *deepcopy_func;

    if (!PyArg_ParseTuple(args, "OOO", &x, &memo, &deepcopy_func))
        return NULL;

    if (!PyTuple_CheckExact(x)) {
        PyErr_SetString(PyExc_TypeError, "expected tuple");
        return NULL;
    }

    Py_ssize_t n = PyTuple_GET_SIZE(x);
    PyObject *y = PyTuple_New(n);
    if (y == NULL) {
        return NULL;
    }

    PyObject *key_memo = PyLong_FromVoidPtr(x);
    if (key_memo == NULL) {
        Py_DECREF(y);
        return NULL;
    }
    if (PyDict_SetItem(memo, key_memo, y) < 0) {
        Py_DECREF(key_memo);
        Py_DECREF(y);
        return NULL;
    }
    Py_DECREF(key_memo);

    for (Py_ssize_t i = 0; i < n; i++) {
        PyObject *item = PyTuple_GET_ITEM(x, i);
        PyObject *new_item = PyObject_CallFunctionObjArgs(
            deepcopy_func, item, memo, NULL);
        if (new_item == NULL) {
            Py_DECREF(y);
            return NULL;
        }
        PyTuple_SET_ITEM(y, i, new_item);  /* steals reference */
    }

    return y;
}

/* --------------------------------------------------------- */
/* Module method table                                       */
/* --------------------------------------------------------- */
static PyMethodDef FastCopyMethods[] = {
    {"deepcopy_list_c", (PyCFunction)deepcopy_list_c, METH_VARARGS,
     "Deepcopy list (C implementation, requires deepcopy func)"},
    {"deepcopy_dict_c", (PyCFunction)deepcopy_dict_c, METH_VARARGS,
     "Deepcopy dict (C implementation, requires deepcopy func)"},
    {"deepcopy_tuple_c", (PyCFunction)deepcopy_tuple_c, METH_VARARGS,
     "Deepcopy tuple (C implementation, requires deepcopy func)"},
    {NULL, NULL, 0, NULL}
};

/* --------------------------------------------------------- */
/* Module definition                                         */
/* --------------------------------------------------------- */
static struct PyModuleDef fastcopymodule = {
    PyModuleDef_HEAD_INIT,
    "fastcopy",
    NULL,
    -1,
    FastCopyMethods
};

PyMODINIT_FUNC
PyInit_fastcopy(void)
{
    return PyModule_Create(&fastcopymodule);
}
