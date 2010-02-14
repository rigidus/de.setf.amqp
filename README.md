<head>
 <title>DE.SETF.AMQP</title>
</head>

DE.SETF.AMQP: a Common Lisp client library for AMQP
-------

`de.setf.amqp` implements a native Common Lisp client library for the 'Advanced Message Queueing
 Protocol'. The implementation comprises wire-level codecs, implementations
 for the standard protocol objects and methods, a functional interface for message-,
 stream- and object-based i/o, and a device-level simple-stream implementation.

 The library targets the revisions of the published AMQP protocol as of versions
 0.8, 0.9, and 0.10. This means that it should work with respective RabbitMQ,
 Apache ActiveMQ, and Qpid implementations. The implementation architecture
 should also accommodate a control structure appropriate for the prospective
 1.0 version - as least as described in preliminary drafts.
 For each version, a distinct package comprises the object and method
 definitions for protocol entities and codecs as generated from the respective
 specification documents.[[1]] Each collection is a
 complete projection, which means there is some amount of duplication.
 The package and directory names names follow more-or-less the naming conventions of the
 xml protocol documents[[2]]:

<table>
<tr><td>AMQP-1-1-0-8-0</td>  <td>version 0.8</td>   <td>[amqp0-8.xml, amqp0-8.pdf (2006-06)]</tr>
<tr><td>AMQP-1-1-0-9-0</td>  <td>version 0.9</td>   <td>[amqp0-9.xml, amqp0-9.pdf (2006-12)]</tr>
<tr><td>AMQP-1-1-0-9-1</td>  <td>version 0.9r1</td> <td>[amqp0-9-1.xml, amqp0-9-1.pdf (2008-11-24)]</tr>
<tr><td>AMQP-1-1-0-10-0</td> <td>version 0.10</td>  <td>[amqp.0-10.xml, amqp.0-10.pdf (2008-02-20)]</tr>
</table>

 In order to modify the translation and/or generate new codecs consult the `:de.setf.amqp.tools` component.

 All protocol versions are expressed through a common interface[[3]] which is specialized for the common
 abstract classes. The initial connection phase determines the correct concrete connection implementation
 to be used to communicate with the broker. Given which the other concrete object and method classes are
 elected from the same package. One determines the version support directly by loading the respective
 version's `.asd` file, which makes its connection class available for negotiation.

 [1]: tools/spec.lisp
 [2]: http://www.amqp.org/confluence/display/AMQP/AMQP+Specification
 [3]: documentation/index.html


Status
------

It would be nice to generate a table similar to [RabbitMQ's](http://www.rabbitmq.com/specification.html). Eventually.
In the meantime, the library has been built and [probed](file:///examples/examples.lisp) in the following combinations

<table>
<tr><td>AMQP broker<br/>lisp implementation</td><th>RabbittMQ</th><th>QPID</th></tr>
<tr><th>MCL</th><td/><td>MCL-5.2, QPID-0.5</td></tr>
<tr><th>CCL</th><td/><td>CCL-1.3, QPID-0.5</td></tr>
<tr><th>SBCL</th><td/><td>SBCL-1.0.35, QPID-0.5</td></tr>
</table>

For example,

    $ sbcl
    This is SBCL 1.0.35, an implementation of ANSI Common Lisp.
    More information about SBCL is available at <http://www.sbcl.org/>.

    * (in-package :amqp.i)

    #<PACKAGE "DE.SETF.AMQP.IMPLEMENTATION">
    * (defparameter *c* (make-instance 'amqp:connection :uri "amqp://guest:guest@localhost/"))

    *C*
    * (defparameter *ch1* (amqp:channel *c* :uri (uri "amqp:///")))

    *CH1*
    * (defparameter *ch1.basic* (amqp:basic *ch1*))

    *CH1.BASIC*
    * (defparameter *ch1.ex* (amqp:exchange *ch1*  :exchange "ex" :type "direct"))

    *CH1.EX*
    * (defparameter *ch1.q*  (amqp:queue *ch1* :queue "q1"))

    *CH1.Q*
    * (amqp:request-declare *ch1.q*)

    #<AMQP-1-1-0-9-1:QUEUE {11D7A0F1}>
    * (amqp:request-bind *ch1.q* :exchange *ch1.ex* :queue *ch1.q* :routing-key "/")

    #<AMQP-1-1-0-9-1:QUEUE {11D7A0F1}>
    * (defparameter *ch2* (amqp:channel *c* :uri (uri "amqp:///")))

    *CH2* 
    * (defparameter *ch2.basic* (amqp:basic *ch2*))

    *CH2.BASIC*
    * (defparameter *ch2.q*  (amqp:queue *ch2* :queue "q1"))

    *CH2.Q*
    * (amqp:request-declare *ch2.q*)

    #<AMQP-1-1-0-9-1:QUEUE {11DA6891}>
    * (list
        (amqp:request-publish *ch1.basic* :exchange *ch1.ex*
                              :body (format nil "this is ~a" (gensym "test #"))
                              :routing-key "/")
        (amqp:request-get *ch2.basic* :queue *ch2.q*))

    ("this is test #1282" "this is test #1624")
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #1820"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #1998"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #2011"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #2014"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #2022"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #2028"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #2179"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    "this is test #1282"
    * (amqp:request-get *ch2.basic* :queue *ch2.q*)

    NIL
    * 

Which, as an aside, indicates that brokered messages persist between connections until they have been consumed.


Licensing
---------

This version is released under version 3 of the GNU Affero license (GAL).[[5]]
The required components are included as per the respective licenses and covered,
in this combined form,  under the GAL as well

- usocket : MIT, through 2007. later work unspecified
  - 2003 Erik Enge
  - 2006-2007 Erik Huelsmann 
- closer-mop : effectively MIT, without the designation
  - 2005 - 2008 Pascal Costanza
- bordeaux-threads : effectively MIT, without designation, with additional attribution undated.[[6]]
  - -2006 Greg Pfeil
- cl-ppcre : equivalent to MIT
  - 2002-2008, Dr. Edmund Weitz
- com.b9.puri : LLGPL, by which com.b9.puri.ppcre is also covered by the LLGPL
  - 1999-2001 Franz, Inc.
  - 2003 Kevin Rosenberg


 [5]: file:///LICENSE
 [6]: http://common-lisp.net/project/bordeaux-threads/darcs/bordeaux-threads/CONTRIBUTORS