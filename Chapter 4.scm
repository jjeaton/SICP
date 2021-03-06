; Prelude: the metacircular evaluator
; Code given:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))
; Need to define that before shadowing apply
(define apply-in-underlying-scheme apply)
(define (apply procedure arguments)
  (cond ((primitive-procedure? procedure)
         (apply-primitive-procedure procedure arguments))
        ((compound-procedure? procedure)
         (eval-sequence
           (procedure-body procedure)
           (extend-environment
             (procedure-parameters procedure)
             arguments
             (procedure-environment procedure))))
        (else
          (error
            "Unknown procedure type -- APPLY" procedure))))
(define (list-of-values exps env)
  (if (no-operands? exps)
    '()
    (cons (eval (first-operand exps) env)
          (list-of-values (rest-operands exps) env))))
(define (eval-if exp env)
  (if (true? (eval (if-predicate exp) env))
    (eval (if-consequent exp) env)
    (eval (if-alternative exp) env)))
(define (eval-sequence exps env)
  (cond ((last-exp? exps) (eval (first-exp exps) env))
        (else (eval (first-exp exps) env)
              (eval-sequence (rest-exps exps) env))))
(define (eval-assignment exp env)
  (set-variable-value! (assignment-variable exp)
                       (eval (assignment-value exp) env)
                       env)
  'ok)
(define (eval-definition exp env)
  (define-variable! (definition-variable exp)
                    (eval (definition-value exp) env)
                    env)
  'ok)
(define (self-evaluating? exp)
  (cond ((number? exp) true)
        ((string? exp) true)
        (else false)))
(define (variable? exp) (symbol? exp))
(define (quoted? exp)
  (tagged-list? exp 'quote))
(define (text-of-quotation exp) (cadr exp))
(define (tagged-list? exp tag)
  (if (pair? exp)
    (eq? (car exp) tag)
    false))
(define (assignment? exp)
  (tagged-list? exp 'set!))
(define (assignment-variable exp) (cadr exp))
(define (assignment-value exp) (caddr exp))
(define (definition? exp)
  (tagged-list? exp 'define))
(define (definition-variable exp)
  (if (symbol? (cadr exp))
    (cadr exp)
    (caadr exp)))
(define (definition-value exp)
  (if (symbol? (cadr exp))
    (caddr exp)
    (make-lambda (cdadr exp)   ; formal parameters
                 (cddr exp)))) ; body
(define (lambda? exp) (tagged-list? exp 'lambda))
(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))
(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)))
(define (if? exp) (tagged-list? exp 'if))
(define (if-predicate exp) (cadr exp))
(define (if-consequent exp) (caddr exp))
(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
    (cadddr exp)
    'false))
(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))
(define (begin? exp) (tagged-list? exp 'begin))
(define (begin-actions exp) (cdr exp))
(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))
(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq))))
(define (make-begin seq) (cons 'begin seq))
(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))
(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))
(define (cond? exp) (tagged-list? exp 'cond))
(define (cond-clauses exp) (cdr exp))
(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else))
(define (cond-predicate clause) (car clause))
(define (cond-actions clause) (cdr clause))
(define (cond->if exp)
  (expand-clauses (cond-clauses exp)))
(define (expand-clauses clauses)
  (if (null? clauses)
    'false                          ; no else clause
    (let ((first (car clauses))
          (rest (cdr clauses)))
      (if (cond-else-clause? first)
        (if (null? rest)
          (sequence->exp (cond-actions first))
          (error "ELSE clause isn't last -- COND->IF"
                 clauses))
        (make-if (cond-predicate first)
                 (sequence->exp (cond-actions first))
                 (expand-clauses rest))))))


;-- 4.1
; These two versions force list-of-value to examine arguments either ltr
; (left-to-right), i.e. the leftmost one first, or rtl (right-to-left)
(define (list-of-values-ltr exps env)
  (if (no-operands? exps)
    '()
    (let ((arg-ltr (eval (first-operand exps) env)))
      (cons arg-ltr
            (list-of-values (rest-operands exps) env)))))
(define (list-of-values-rtl exps env)
  (if (no-operands? exps)
    '()
    (let ((arg-rtl (list-of-values (rest-operands exps) env)))
      (cons (eval (first-operand exps) env)
            arg-rtl))))

;-- 4.2
; a. If we put procedure application before assignment, (define x 3) will try
; to call the procedure define with arguments x and 3, which won't work because
; x is undefined.

; b.
; First, we'll change eval to fit the new order:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        (else
          (error "Unknown expression type -- EVAL" exp))))
; Now we have to modify the application? function:
(define (application? exp)
  (tagged-list? exp 'call))
; And its helpers:
(define (operator exp) (cadr exp))
(define (operands exp) (cddr exp))

;-- 4.3
; Rewrite eval so that the dispatch is done in data-directed style.
; We'll use MIT Scheme's hash-table implementation
(define operators (make-eq-hash-table))
(define (put-operator op action)
  (hash-table/put! operators op action))
(define (operator-exists? op)
  (hash-table/lookup operators op (lambda (_) #t) (lambda () #f)))
(define (get-operation op)
  (hash-table/get operators op '()))
(put-operator 'quote
              (lambda (exp env) (text-of-quotation exp)))
(put-operator 'set!
              (lambda (exp env) (eval-assignment exp env)))
(put-operator 'define
              (lambda (exp env) (eval-definition exp env)))
(put-operator 'if
              (lambda (exp env) (eval-if exp env)))
(put-operator 'lambda
              (lambda (exp env)
                (make-procedure (lambda-parameters exp)
                                (lambda-body exp)
                                env)))
(put-operator 'begin
              (lambda (exp env) (eval-sequence (begin-actions exp) env)))
(put-operator 'cond
              (lambda (exp env) (eval (cond->if exp) env)))

(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ; Data-directed dispatch:
        ((operator-exists? (car exp))
         ((get-operation (car exp)) exp env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))

; Okay, now we'd better test all of that.
; We're missing the following methods:
(define (lookup-variable-value var env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (car vals))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
      (error "Unbound variable" var)
      (let ((frame (first-frame env)))
        (scan (frame-variables frame)
              (frame-values frame)))))
  (env-loop env))
(define (enclosing-environment env) (cdr env))
(define (first-frame env) (car env))
(define the-empty-environment '())
(define (setup-environment)
  (let ((initial-env
          (extend-environment (primitive-procedure-names)
                              (primitive-procedure-objects)
                              the-empty-environment)))
    (define-variable! 'true true initial-env)
    (define-variable! 'false false initial-env)
    initial-env))
(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive))
(define (primitive-implementation proc) (cadr proc))
(define primitive-procedures
  (list (list 'car car)
        (list 'cdr cdr)
        (list 'cons cons)
        (list 'null? null?)
        (list '+ +)))
(define (primitive-procedure-names)
  (map car
       primitive-procedures))
(define (primitive-procedure-objects)
  (map (lambda (proc) (list 'primitive (cadr proc)))
       primitive-procedures))
(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
    (cons (make-frame vars vals) base-env)
    (if (< (length vars) (length vals))
      (error "Too many arguments supplied" vars vals)
      (error "Too few arguments supplied" vars vals))))
(define (make-frame variables values)
  (cons variables values))
(define (frame-variables frame) (car frame))
(define (frame-values frame) (cdr frame))
(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))))
(define (set-variable-value! var val env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
      (error "Unbound variable -- SET!" var)
      (let ((frame (first-frame env)))
        (scan (frame-variables frame)
              (frame-values frame)))))
  (env-loop env))
(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (add-binding-to-frame! var val frame))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (scan (frame-variables frame)
          (frame-values frame))))
(define true #t)
(define false #f)

(define (make-procedure parameters body env)
  (list 'procedure parameters body env))
(define (compound-procedure? p)
  (tagged-list? p 'procedure))
(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))
(define (apply-primitive-procedure proc args)
  (apply-in-underlying-scheme
    (primitive-implementation proc) args))
(define the-global-environment (setup-environment))


; Phew, finally:
(eval '(+ 2 3) the-global-environment)
; 5
; Awesome!

;-- 4.4
; First, we have to modify eval:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((and? exp) (eval-and exp env))
        ((or? exp) (eval-or exp env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))

; Then we can write and and or helper functions:
(define (and? exp)
  (tagged-list? exp 'and))
(define (or? exp)
  (tagged-list? exp 'or))
(define (eval-and exps env)
  (define (eval-operands exps env)
    (cond ((null? exps) #t)
          ((eval (first-exp exps) env)
           (eval-operands (rest-exps exps) env))
          (else #f)))
  (eval-operands (rest-exps exps) env))
(define (eval-or exps env)
  (define (eval-operands exps env)  
    (cond ((null? exps) #f)
          ((eval (first-exp exps) env) #t)
          (else
           (eval-operands (rest-exps exps) env))))
  (eval-operands (rest-exps exps) env))

; Tests:
(eval '(and true true) the-global-environment)
(eval '(and false true true) the-global-environment)
(eval '(or false false false true false) the-global-environment)
(eval '(or false false false) the-global-environment)

; As derived expressions:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((and? exp) (eval (and->if exp) env))
        ((or? exp) (eval (or->if exp) env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))
; and? and or? are the same as above:
(define (and? exp)
  (tagged-list? exp 'and))
(define (or? exp)
  (tagged-list? exp 'or))
; But this is new:
(define (and->if exps)
  (define (expand-and exps)
    (if (null? exps)
      'true
      (make-if (first-exp exps)
               (expand-and (rest-exps exps))
               'false)))
  (expand-and (rest-exps exps)))
(define (or->if exps)
  (define (expand-or exps)
    (if (null? exps)
      'false
      (make-if (first-exp exps)
               'true
               (expand-or (rest-exps exps)))))
  (expand-or (rest-exps exps)))

; Strangely enough, we also need to add this:
(define (true? b) (not (eq? b #f)))

; Same tests as above:
(eval '(and true true) the-global-environment)
(eval '(and false true true) the-global-environment)
(eval '(or false false false true false) the-global-environment)
(eval '(or false false false) the-global-environment)

;-- 4.5
; We must support the syntax:
; (cond ((assoc 'b '((a 1) (b 2))) => cadr)
;       (else false))

; We add the helper functions:
(define (cond-arrow-form? clause)
  (eq? (car (cond-actions clause)) '=>))
(define (cond-arrow-action clause)
  (caddr clause))
; And modify expand-clauses as follows:
(define (expand-clauses clauses)
  (if (null? clauses)
    'false
    (let ((first (car clauses))
          (rest (cdr clauses)))
      ; We replace the simple if by a ternary cond: our clause can be either an
      ; else, an arrow, or a standard clause
      (cond ((cond-else-clause? first)
             (if (null? rest)
               (sequence->exp (cond-actions first))
               (error "ELSE clause isn't last -- COND->IF"
                      clauses)))
            ((cond-arrow-form? first)
             (make-if (cond-predicate first)
                      (list (cond-arrow-action first)
                            (cond-predicate first))
                      (expand-clauses rest)))
            (else
              (make-if (cond-predicate first)
                       (sequence->exp (cond-actions first))
                       (expand-clauses rest)))))))

; Tests:
(eval '(cond ((+ 1 1) => quote)
             (false => quote)
             (else 1))
      the-global-environment)
; (+ 1 1)
(eval '(cond (false => quote)
             ((+ 2 2) => quote)
             (else 1))
      the-global-environment)
; (+ 2 2)

;-- 4.6
; Support for let
(define (let? exp)
  (tagged-list? exp 'let))
(define let-body cddr)
(define let-associations cadr)
(define (let-symbols exp)
  (map car (let-associations exp)))
(define (let-values exp)
  (map cadr (let-associations exp)))
(define (let->combination exp)
  (cons (make-lambda (let-symbols exp)
                     (let-body exp))
        (let-values exp)))
; Tests:
(let->combination '(let ((a (+ 1 5))) (+ a 1)))
; ((lambda (a) (+ a 1)) (+ 1 5))

; Now we redefine eval:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((let? exp) (eval (let->combination exp) env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))

(eval '(let ((a (+ 1 5))) (+ a 1)) the-global-environment)
; 7

;-- 4.7
; let*
(define (make-let assocs body)
  (list 'let assocs body))
(define (let*? exp)
  (tagged-list? exp 'let*))
(define (make-recursive-let assocs body)
  (if (null? assocs)
    (car body)
    (make-let (list (car assocs))
              (make-recursive-let (cdr assocs) body))))
(define (let*->nested-lets exp)
  (make-recursive-let (let-associations exp) (let-body exp)))

; Test:
(let*->nested-lets '(let* ((a 1) (b (+ a 1))) b))
; (let ((a 1)) (let ((b (+ a 1))) b))

; Now we redefine eval:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((let*? exp) (eval (let*->nested-lets exp) env))
        ((let? exp) (eval (let->combination exp) env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))

; Test:
(eval '(let* ((a 1) (b (+ a 1))) b) the-global-environment)
; 2

; As we show, it is indeed possible to evaluate let* in terms of derived
; expressions (actually, derived derived expressions, because a let* is
; derived in several let which are in turn derived in lambdas).
; This is due to the recursive nature of eval.

;-- 4.8
; Named let

; From 4.6:
(define (let? exp)
  (tagged-list? exp 'let))
(define let-body cddr)
(define let-associations cadr)
(define (let-symbols exp)
  (map car (let-associations exp)))
(define (let-values exp)
  (map cadr (let-associations exp)))
; Added:
(define (named-let? exp)
  (not (list? (let-associations exp))))
(define named-let-fun cadr)
(define named-let-associations caddr)
(define named-let-body cdddr)
(define (named-let-symbols exp)
  (map car (named-let-associations exp)))
(define (named-let-values exp)
  (map cadr (named-let-associations exp)))
(define (define-let-fun exp)
  (list 'define
        (cons (named-let-fun exp)
              (named-let-symbols exp))
        (car (named-let-body exp))))
; Modified:
(define (let->combination exp)
  (cond ((named-let? exp)
         (cons (make-lambda (named-let-symbols exp)
                            (cons (define-let-fun exp)
                                  (list (cons (named-let-fun exp)
                                              (named-let-symbols exp)))))
               (named-let-values exp)))
        (else
          (cons (make-lambda (let-symbols exp)
                             (let-body exp))
                (let-values exp)))))

; Test:
(define named-let-test '(let fib-iter ((a 1)
                                       (b 0)
                                       (count n))
                          (if (= count 0)
                            b
                            (fib-iter (+ a b) a (- count 1)))))
(let->combination named-let-test)
; ((lambda (a b count) (define (fib-iter a b count) (if (= count 0) b (fib-iter (+ a b) a (- count 1)))) (fib-iter a b count)) 1 0 n)

; Let's reindent that to see if it's correct:
((lambda (a b count)
   (define (fib-iter a b count)
     (if (= count 0)
       b
       (fib-iter (+ a b) a (- count 1))))
   (fib-iter a b count))
 1 0 n)

(eval '(define (fib n)
         (let fib-iter ((a 1)
                        (b 0)
                        (count n))
           (if (= count 0)
             b
             (fib-iter (+ a b) a (- count 1)))))
      the-global-environment)
; ok
(eval '(fib 5) the-global-environment)
;Unbound variable =

; Darn. Can't test this, = is not part of our environment.
; That said, we can try the combinator by executing the generated code in
; another Scheme:
(define n 20)
((lambda (a b count)
   (define (fib-iter a b count)
     (if (= count 0)
       b
       (fib-iter (+ a b) a (- count 1))))
   (fib-iter a b count))
 1 0 n)
; 6765
; Correct!

;-- 4.9
; Let's create for.
; It should be called this way:
(for ((define i 0) (< i 5) (set! i (+ i 1)))
     (display i))
; And "compile" down to a recursive function.

(define (for? exp)
  (tagged-list? exp 'for))
(define for-params cadr)
(define (for-init exp)
  (car (for-params exp)))
(define (for-cond exp)
  (cadr (for-params exp)))
(define (for-iter exp)
  (caddr (for-params exp)))
(define for-body caddr)
(define (for-recursion exp)
  (list 'define ; NB: we could write a make-definition
        (list 'recurse)
        (list 'if ; ... and adapt make-if to support alternative-less ifs
              (for-cond exp)
              (make-begin (list (for-body exp)
                                (for-iter exp)
                                (list 'recurse))))))
(define (for->combination exp)
  (list (make-lambda '()
                     (list (for-init exp)
                           (for-recursion exp)
                           (list 'recurse)))))

; Test:
(define for-test '(for ((define i 0) (< i 5) (set! i (+ i 1))) (display i)))
(for->combination for-test)
; Gives:
((lambda ()
   (define i 0)
   (define (recurse)
     (if (< i 5)
       (begin (display i)
              (set! i (+ i 1))
              (recurse))))
   (recurse)))
; Given set! and display aren't defined in our implementation, we can execute
; the generated code in another Scheme to see that it works:
; 01234

;-- 4.10
; Let's say we change the syntax of if to strange-if, defined as:
; (strange-if consequent predicate alternative)
; We only have to change:
(define (if? exp) (tagged-list? exp 'strange-if))
(define (if-predicate exp) (caddr exp))
(define (if-consequent exp) (cadr exp))
(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
    (cadddr exp)
    'false))
(define (make-if predicate consequent alternative)
  (list 'strange-if consequent predicate alternative))

; Test:
(eval '(strange-if true (+ 1 1) false) the-global-environment)
; #t

;-- 4.11
; Instead of representing a frame as a pair of lists, we can represent a frame
; as a list of bindings, where each binding is a name-value pair. 
(define (make-frame variables values)
  (zip variables values))
(define (frame-variables frame) (map car frame))
(define (frame-values frame) (map cadr frame))
(define (add-binding-to-frame! var val frame)
  (set-cdr! frame (cons (car frame) (cdr frame)))
  (set-car! frame (list var val)))

; Let's try:
(eval '(+ 2 3) the-global-environment)
; Value: 5
; Good!
(eval '(define a 10) the-global-environment)
; Value: ok
; Good!
(eval 'a the-global-environment)
; 10
; Perfect!

;-- 4.12
(define (lookup-variable-value var env)
  (define (env-loop env)
    (if (eq? env the-empty-environment)
      (error "Unbound variable" var)
      (let ((frame (first-frame env)))
        (scan frame
              var
              '()
              #f
              (lambda ()
                (env-loop (enclosing-environment env)))))))
  (env-loop env))
(define (set-variable-value! var val env)
  (define (env-loop env)
    (if (eq? env the-empty-environment)
      (error "Unbound variable -- SET!" var)
      (let ((frame (first-frame env)))
        (scan frame
              var
              val
              #t
              (lambda ()
                (env-loop (enclosing-environment env)))))))
  (env-loop env))
(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (scan frame
          var
          val
          #t
          (lambda ()
            (add-binding-to-frame! var val frame)))))
; These three methods all perform a search of the environment.
(define (scan frame var val set callback)
  (define (scan-iter vars vals)
    (cond ((null? vars)
           (callback))
          ((eq? var (car vars))
           (if set
             (set-car! vals val)
             (car vals)))
          (else (scan-iter (cdr vars) (cdr vals)))))
  (scan-iter (frame-variables frame) (frame-values frame)))

; Test:
(eval '(define b 10) the-global-environment)
; ok
(eval 'b the-global-environment)
; 10

;-- 4.13
; Design an un-binding mechanism
; Helper functions:
(define (undefinition? exp)
  (tagged-list? exp 'make-unbound!))
(define (undefinition-variable exp) (cadr exp))
(define (eval-undefinition exp env)
  (undefine-variable! (undefinition-variable exp)
                      env)
  'ok)
; Reminder: our variable list for each is composed of two lists: one containing
; the variable names, the other containing the actual values.
; We'll only look for the variable in the first frame.
(define (undefine-variable! var env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (error "Variable does not exist -- MAKE-UNBOUND!" var))
            ((eq? var (car vars)) ; Remove binding:
             (set-car! vars (cdr vars)))
            (else (scan (cdr vars) (cdr vals)))))
    (scan (frame-variables frame)
          (frame-values frame))))
; Then we redefine eval:
(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((undefinition? exp) (eval-undefinition exp env))
        ((if? exp) (eval-if exp env))
        ((let? exp) (eval (let->combination exp) env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp) 
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknown expression type -- EVAL" exp))))

; Test:
(eval 'a the-global-environment)
; Unbound variable a
(eval '(define a 12) the-global-environment)
;Value: ok
(eval 'a the-global-environment)
;Value: 12
(eval '(make-unbound! a) the-global-environment)
;Value: ok
(eval 'a the-global-environment)
; Unbound variable a

;-- 4.14
; Eva's version works as intended because it is interpreted inside the Scheme
; interpreter we wrote. However, Louis' version calls the underlying Scheme's
; "apply", instead of our interpreted "apply"... Hence things going awry.

;-- 4.15
; Given a one-argument procedure p and an object a, p is said to ``halt'' on a
; if evaluating the expression (p a) returns a value (as opposed to terminating
; with an error message or running forever). Show that it is impossible to
; write a procedure halts? that correctly determines whether p halts on a for
; any procedure p and object a. Use the following reasoning: If you had such a
; procedure halts?, you could implement the following program: 
(define (run-forever) (run-forever))
(define (try p)
  (if (halts? p p)
      (run-forever)
      'halted))
; Now consider evaluating the expression (try try) and show that any possible
; outcome (either halting or running forever) violates the intended behavior of
; halts?

; The two possible outcomes when we run (try try) are:
; - (try try) runs forever: it means that the condition inside try has been
; found correct, i.e. that (halts? try try) is true. But we hypothesised it
; runs forever. Contradiction.
; - (try try) returns 'halted: it means that the condition inside try has been
; found false, i.e. that (halts? try try) is false. But we hypothesised it does
; halt. Contradition.

;-- 4.16
; (Uses let from 4.6 and functions defined in 4.12)
; a.
(define (lookup-variable-value var env)
  (define (env-loop env)
    (if (eq? env the-empty-environment)
      (error "Unbound variable" var)
      (let ((frame (first-frame env)))
        (scan frame
              var
              '()
              #f
              (lambda ()
                (env-loop (enclosing-environment env)))))))
  (let ((value (env-loop env)))
    (if (eq? value '*unassigned*)
      (error "Unassigned value for variable:" var)
      value)))
; Test:
(eval '(define a '*unassigned*) the-global-environment)
; ok
(eval 'a the-global-environment)
; *** ERROR IN (console)@568.1 -- Unassigned value for variable: a

; b.
; Helper functions, if they're not defined in your Scheme:
(define (filter predicate list)
  (cond ((null? list) '())
        ((predicate (car list))
         (cons (car list) (filter predicate (cdr list))))
        (else
          (filter predicate (cdr list)))))
(define (last list)
  (cond ((null? list) '())
        ((null? (cdr list)) (car list))
        (else (last (cdr list)))))
(define (zip a b)
  (if (null? a)
    '()
    (cons (list (car a) (car b)) (zip (cdr a) (cdr b)))))
(define (scan-out-defines body)
  (let* ((definitions (filter definition? body))
         (rest-of-lambda (cdr (memq (last definitions) body)))
         (symbols (map cadr definitions))
         (bodies (map caddr definitions)))
    (append (list 'let
                  (map (lambda (s) (cons s (cons '*unassigned* '())))
                       symbols))
            (map (lambda (s) (list 'set! (cadr s) (caddr s)))
                 definitions)
            rest-of-lambda)))
; Test:
(define test '((define u true)
               (define v false)
               (its-the-lambda-rest)))
(scan-out-defines test)
; (let ((u *unassigned*) (v *unassigned*))
;   (set! u true)
;   (set! v false)
;   (its-the-lambda-rest))

; All good.

; c.
(define (procedure-body p)
  (scan-out-defines (caddr p)))
; Test:
(define test '(lambda (a b c)
  (define u 1)
  (define v 3)
  (+ u v)))
(eval test the-global-environment)
; Does a procedure as expected.
(define test2 '(define (ll a b c)
  (define d 1)
  (+ a b c d)))
(eval test2 the-global-environment)
(eval '(ll 1 2 3) the-global-environment)

; Alright, so. This code is wrong. It blows up somewhere between evaluating and
; executing, as far as I can tell. I spent too much time staring blankly at the
; code already; to fix someday.

;-- 4.17
; (Imagine drawings)

;-- 4.18
; This will work in 4.16's way, but not in the alternative strategy.

;-- 4.19
; I support Ben's point of view. f is a closure over the bound variable a, which
; gets overwritten in the function scope when redefined. 4.16's behaviour is
; indeed as described by Alyssa, but should stay an implementation detail.
; This is very much of a procedural-oriented way of thinking, because it doesn't
; satisfy the condition of simultaneity that should be part of a suite of 
; definitions.
; Eva's way is the best, but is hard to implement: it would require definitions
; to be processed in a certain order, and/or to be scanned out for
; yet-unprocessed definitions and put on hold until those have been evaluated.

;-- 4.20
;

;-- 4.21
; Haaa! That's the Y Combinator! *brain 'splodes*
; Putting this part of Chapter 4 on hold until my brain gets bigger.



;-- 4.25
(define (unless condition usual-value exceptional-value)
  (if condition exceptional-value usual-value))
(define (factorial n)
  (unless (= n 1)
          (* n (factorial (- n 1)))
          1))
(factorial 5)
; This never stops. Why?
; After all, it we transpose unless as if, it gives:
(define (if-factorial n)
  (if (= n 1)
    1
    (* n (if-factorial (- n 1)))))
; And that works. So where's the catch?

; The catch is in applicative-order.
; When we want to apply factorial, we apply unless and eval its arguments. But
; one of these arguments is factorial, which contains an unless, which is
; converted to an if. But this if also has factorial which has an unless which
; needs to be converted to an if - and so on ad infinitum.

; With lazy evaluation, factorial would be evaluated once when n is 5. Then
; evaluated a second time when n is 4, and so on until n is 1 and we don't need
; to eval factorial any more.

;-- 4.26
; Ben's solution is easy. I don't think I understand Alyssa's solution.

;-- 4.27
(define count 0)
(define (id x)
  (set! count (+ count 1))
  x)
(define w (id (id 10)))
;;; L-Eval input:
count
;;; L-Eval value:
0
; Nothing has been evaluated yet. w received a mere thunk, but has not been 
; executed because of laziness.
;;; L-Eval input:
w
;;; L-Eval value:
10
; id returns its input value, in this case the value of the (now executed)
; (id 10) thunk.
;;; L-Eval input:
count
;;; L-Eval value:
2
; The two (id) and their side-effects have been forced to execute due to
; evaluating w

;-- 4.28
(define (alittlebitsofternow) -)
(define (alittlebitfasternow) +)
(define shout #t)
(define (speed)
  (if shout
    (alittlebitsofternow)
    (alittlebitfasternow)))
(define (songpart)
  ((speed) 1 1))

; We have to evaluate the operator (speed) here. If we didn't, we wouldn't know
; how to apply those arguments to a thunk.

;-- 4.29
; Canonical example is the naive fibonacci:
(define (fibonacci n)
  (if (or (= n 0)
          (= n 1))
    1
    (+ (fibonacci (- n 1))
       (fibonacci (- n 2)))))

; As is, this function does an exponential number of function calls — which is
; bad. Memoizing allows us to cut that number dramatically and make the number
; of function calls O(n)

(define (square x)
  (* x x))
;;; L-Eval input:
(square (id 10))
;;; L-Eval value:
100
;;; L-Eval input:
count
;;; L-Eval value:
; With memoization:
1 ; because (id 10) has been called once and memoized
; Without:
2 ; because (id 10) has been called twice

;-- 4.30
; I don't know.

;-- 4.31
; Insert large rewrite of the interpreter.

;-- 4.32
; Making the car as lazy as the cdr allows for completely-lazy data structures,
; such as trees. Before that, we'd have had to make sure the car was something
; easily computable and/or small, because it'd be evaluated as soon as the
; element is accessed - now it can be lazy.

;-- 4.33
; '(a b) is seen by the parser as (quote (a b)). This leaves out our tuned cons
; and makes both approaches incompatible.
; The solution is to replace the parser of quotations in a way that it'll
; provide lazy lists that we can manipulate with the lazy car and the lazy cdr.

;-- 4.34
; You're on your own, buddy.

;-- 4.35
; At first, I wanted to use:
(define (an-integer-between low high)
  (if (= low high)
    high
    (amb low (an-integer-between (+ low 1) high))))
; But is seems more in the spirit of the chapter to write:
(define (an-integer-between low high)
  (require (<= low high))
  (amb low (an-integer-between (+ low 1) high)))

;-- 4.36
; This won't work due to the way amb works. Depth-first backtracking means that
; amb will try values of i, j, k as (1 1 1) first, then (1 1 2), then (1 1 3),
; etc, trying to cover all the possible values of k.

; Instead, we can write:
(define (pythagorean-triples)
  (letrec ((k (an-integer-starting-from 1))
           (j (an-integer-between 1 k))
           (i (an-integer-between 1 j)))
    (require (= (+ (* i i) (* j j)) (* k k)))
    (list i j k)))
; Here, we're inverting the order of integers to use depth-first search to our
; advantage. amb will start by incrementing i, then j, and k in last resort,
; yielding all the possible triplets that can give pythagorean numbers. These
; triplets will then be checked to be pythagorean by the 'require' clause.

;-- 4.37
; Yes, Ben's technique is more efficient: he adds i² and j², then checks if the
; square root of this sum (an hypothetical k) is an integer. This allows him to
; only iterate on two values instead of three, i.e. for a given i and j, he
; doesn't have to go through several values of k to determine if this is a
; pythagorean triple or not.
;
; Another optimisation is discarding every (i, j) combination where
; i²+j² > high², a case where no solution would be acceptable.


