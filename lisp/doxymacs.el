;; doxymacs.el
;;
;; $Id: doxymacs.el,v 1.23 2001/04/30 04:41:46 ryants Exp $
;;
;; ELisp package for making doxygen related stuff easier.
;;
;; Copyright (C) 2001 Ryan T. Sammartino
;; http://members.home.net/ryants/
;; ryants@home.com
;;
;; Doxymacs homepage: http://doxymacs.sourceforge.net/
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

;;
;; ChangeLog
;;
;; 29/03/2001 - The doxytags.pl PERL script is no longer necessary, as we can
;;              now parse the XML file that doxygen creates directly.
;; 22/04/2001 - Function documentation.
;; 18/04/2001 - Going with Kris' "new style" look up code.  It's excellent.
;;            - Incorprated Andreas Fuchs' patch for loading tags from a
;;              URL.
;; 11/04/2001 - added ability to insert blank doxygen comments with either
;;              Qt or JavaDoc style.
;;            - also did "file" comments
;; 31/03/2001 - added ability to choose which symbol to look up if more than
;;              one match
;;            - slightly changed the format of the list that 
;;              doxymacs-get-matches returns
;; 28/03/2001 - added doxymacs to the "tools" customisation group.
;;            - removed doxymacs-browser (just use user's default browser)
;;            - minor formatting updates
;; 24/03/2001 - initial version.  Pretty lame.  Need some help.

;; TODO
;;
;; - 'user' styles for inserting comments
;; - add some default key-bindings 
;; - error checking (invalid tags file format, etc).
;; - test this on other versions of {X}Emacs other than the one I'm 
;;   using (XEmacs 21.1.14)
;; - other stuff?

;; Front matter and variables

(provide 'doxymacs)

(require 'custom)
(require 'xml-parse)
(require 'url)
(require 'w3-cus)

(defgroup doxymacs nil
  "Find documentation for symbol at point"
  :group 'tools)

(defcustom doxymacs-doxygen-root
  "file:///home/ryants/projects/doxymacs/example/doc/html/"
  "*Root for doxygen documentation (URL)"
  :type 'string
  :group 'doxymacs)

(defcustom doxymacs-doxygen-tags
;  "http://members.home.net/ryants/doxy.tag"
;  "file:/home/ryants/projects/doxymacs/example/doc/doxy.tag"
  "../example/doc/doxy.tag"
  "*File name or URL that contains doxygen tags"
  :type 'string
  :group 'doxymacs)

(defcustom doxymacs-doxygen-style
  "JavaDoc"
  "*The style of comments to insert into code"
  :type '(radio (const :tag "JavaDoc" "JavaDoc") (const :tag "Qt" "Qt"))  
  :group 'doxymacs)

(defvar doxymacs-tags-buffer nil
  "The buffer with our doxytags")

;; The structure of this list has been chosen for ease of use in the
;; completion functions.  The structure is as follows:
;; ( (symbol-1 . ((description-1a . url-1a) (description-1b . url-1b)))
;;   (symbol-2 . ((description-2a . url-2a)))
;;   ... )
(defvar doxymacs-completion-list nil
  "The list with doxytags completions")

(defvar doxymacs-completion-buffer "*Completions*"
  "The buffer used for displaying multiple completions")


;;These functions have to do with looking stuff up in doxygen generated
;;documentation

;;doxymacs-load-tag
;;This loads the tags file generated by doxygen into the buffer *doxytags*.  
(defun doxymacs-load-tags ()
  "Loads a tags file"
  (if (or (eq doxymacs-tags-buffer nil)
	  (eq (buffer-live-p doxymacs-tags-buffer) nil))
      (progn
	(setq doxymacs-tags-buffer (generate-new-buffer "*doxytags*"))
	(let ((currbuff (current-buffer)))
	  (if (file-regular-p doxymacs-doxygen-tags)
	      ;;It's a regular file, so just grab it.
	      (progn
		(set-buffer doxymacs-tags-buffer)
		(insert-file-contents doxymacs-doxygen-tags))
	    ;; Otherwise, try and grab it as a URL
	    (progn
	      (if (url-file-exists doxymacs-doxygen-tags)
		  (progn
		    (set-buffer doxymacs-tags-buffer)
		    (url-insert-file-contents doxymacs-doxygen-tags)
		    (set-buffer-modified-p nil))
		(error (concat doxymacs-doxygen-tags " not found.")))))
	  (set-buffer currbuff)))))

(defun doxymacs-add-to-completion-list (symbol desc url)
  "Add a symbol to our completion list, along with its description and URL"
  (let ((check (assoc symbol doxymacs-completion-list)))
    (if check
	;; There is already a symbol with the same name in the list
	(if (not (assoc desc (cdr check)))
	    ;; If there is not yet a symbol with this desc, add it
	    ;; FIXME: what to do if there is already a symbol??
	    (setcdr check (cons (cons desc url)
				(cdr check))))
      ;; There is not yet a symbol with this name in the list
      (setq doxymacs-completion-list
	    (cons (cons symbol (list (cons desc url)))
		  doxymacs-completion-list)))))


(defun doxymacs-fill-completion-list ()
  "Load and parse the tags from the *doxytags* buffer, constructing our 
doxymacs-completion-list from it"
  (doxymacs-load-tags)
  (let ((currbuff (current-buffer)))
    (set-buffer doxymacs-tags-buffer)
    (goto-char (point-min))
    (setq doxymacs-completion-list nil)
    (let ((xml (read-xml))) ;; Parse the XML file
      (let ((compound-list (xml-tag-children xml)))
	(if (not (string= (xml-tag-name xml) "tagfile"))
	    (error (concat "Invalid tag file: " doxymacs-doxygen-tags))
	  ;; Go through the compounds, adding them and their members to the
	  ;; completion list.
	  (while compound-list
	    (let* ((curr-compound (car compound-list))
		   (compound-name (cadr (xml-tag-child curr-compound "name")))
		   (compound-kind (xml-tag-attr curr-compound "kind"))
		   (compound-url (cadr 
				  (xml-tag-child curr-compound "filename")))
		   (compound-desc (concat compound-kind " " compound-name))
		   (compound-members (doxymacs-get-compound-members 
				      curr-compound)))
	      ;; Add this compound to our completion list
	      (doxymacs-add-to-completion-list compound-name
					       compound-desc
					       compound-url)
	      ;; Add its members
	      (doxymacs-add-compound-members compound-members 
					     compound-name
					     compound-url)
	      
	      ;; On to the next compound
	      (setq compound-list (cdr compound-list)))))))
      ;; Don't need the doxytags buffer anymore
      (kill-buffer doxymacs-tags-buffer)
      (set-buffer currbuff)))

(defun doxymacs-get-compound-members (compound)
  "Get the members of the given compound"
  (let ((children (xml-tag-children compound))
	(members nil))
    ;; Run through the children looking for ones with the "member" tag
    (while children
      (let* ((curr-child (car children)))
	(if (string= (xml-tag-name curr-child) "member")
	    ;; Found a member.  Throw it on the list.
	    (setq members (cons curr-child members)))
	(setq children (cdr children))))
    members))

(defun doxymacs-add-compound-members (members compound-name compound-url)
  "Add the members of the coumpound with compound-name and compound-url"
  (while members
    (doxymacs-add-compound-member (car members) compound-name compound-url)
    (setq members (cdr members))))

(defun doxymacs-add-compound-member (member compound-name compound-url)
  "Add a single member of the given compound"
  ;; Get all the juicy info out of the XML tags for this member.
  (let* ((member-name (cadr (xml-tag-child member "name")))
	 (member-anchor (cadr (xml-tag-child member "anchor")))
	 (member-url (concat compound-url "#" member-anchor))
	 (member-args (if (cdr (xml-tag-child member "arglist"))
			  (cadr (xml-tag-child member "arglist"))
			""))
	 (member-desc (concat compound-name "::" member-name member-args)))
    (doxymacs-add-to-completion-list member-name
				     member-desc
				     member-url)))
  	
(defun doxymacs-display-url (url)
  "Displays the given match"
  (browse-url (concat doxymacs-doxygen-root "/" url)))

(defun doxymacs-lookup (symbol)
  "Look up the symbol under the cursor in doxygen"
  (interactive 
   (save-excursion
     (if (eq doxymacs-completion-list nil)
	 ;;Build our completion list if not already done
	 (doxymacs-fill-completion-list))
     (let ((symbol (completing-read 
		    "Look up: " 
		    doxymacs-completion-list nil nil (symbol-near-point))))
	 (list symbol))))
  (let ((url (doxymacs-symbol-completion symbol doxymacs-completion-list)))
    (if url
        (doxymacs-display-url url))))

(defun doxymacs-symbol-completion (initial collection &optional pred)
  "Do completion for given symbol"
  (let ((completion (try-completion initial collection pred)))
    (cond ((eq completion t)
           ;; Only one completion found.  Validate it.
           (doxymacs-validate-symbol-completion initial collection pred))
          ((null completion)
           ;; No completion found
           (message "No documentation for '%s'" initial)
           (ding))
          (t
           ;; There is more than one possible completion
           (let ((matches (all-completions initial collection pred)))
             (with-output-to-temp-buffer doxymacs-completion-buffer
               (display-completion-list (sort matches #'string-lessp))))
           (let ((completion (completing-read 
			      "Select: " 
			      collection pred nil initial)))
             (delete-window (get-buffer-window doxymacs-completion-buffer))
             (if completion
                 ;; If there is a completion, validate it.
                 (doxymacs-validate-symbol-completion 
		  completion collection pred)
               ;; Otherwise just return nil
               nil))))))

(defun doxymacs-validate-symbol-completion (initial collection &optional pred)
  "Checks whether the symbol (initial) has multiple descriptions, and if so
continue completion on those descriptions.  In the end it returns the URL for
the completion or nil if canceled by the user."
  (let ((new-collection (cdr (assoc initial collection))))
    (if (> (length new-collection) 1)
        ;; More than one
        (doxymacs-description-completion "" new-collection pred)
      ;; Only one, return the URL
      (cdar new-collection))))

(defun doxymacs-description-completion (initial collection &optional pred)
  "Do completion for given description"
  (let ((matches (all-completions initial collection pred)))
    (with-output-to-temp-buffer doxymacs-completion-buffer
      (display-completion-list (sort matches #'string-lessp))))
  (let ((completion (completing-read "Select: " collection pred nil initial)))
    (delete-window (get-buffer-window doxymacs-completion-buffer))
    (if completion
        ;; Return the URL if there is a completion
        (cdr (assoc completion collection)))))

;;This is mostly a convenience function for the user
(defun doxymacs-rescan-tags ()
  "Rescan the tags file"
  (interactive)
  (if (buffer-live-p doxymacs-tags-buffer)
      (kill-buffer doxymacs-tags-buffer))
  (doxymacs-fill-completion-list))


;; These functions have to do with inserting doxygen commands in code

;; So the non-interactive functions return a pair:
;; the car is the string to insert, the cdr is the number of lines
;; to skip.

(defun doxymacs-blank-multiline-comment ()
  (if (equal doxymacs-doxygen-style "JavaDoc")
      (cons "/**\n * \n * \n */\n" 2)
    (cons "//! \n/*!\n \n*/\n" 1)))

(defun doxymacs-insert-blank-multiline-comment ()
  "Inserts a multi-line blank doxygen comment at the current point"
  (interactive "*")
  (let ((comment (doxymacs-blank-multiline-comment)))
    (save-excursion 
      (beginning-of-line)    
      (let ((start (point)))    
	(insert (car comment))
	(let ((end (point)))
	  (indent-region start end nil))))
    (end-of-line (cdr comment))))

(defun doxymacs-blank-singleline-comment ()
  (if (equal doxymacs-doxygen-style "JavaDoc")
      (cons "/// " 1)
    (cons "//! " 1)))

(defun doxymacs-insert-blank-singleline-comment ()
  "Inserts a single-line blank doxygen comment at current point"
  (interactive "*")
  (let ((comment (doxymacs-blank-singleline-comment)))
    (save-excursion
      (beginning-of-line)
      (let ((start (point)))
	(insert (car comment))
	(let ((end (point)))
	  (indent-region start end nil))))
    (end-of-line (cdr comment))))

(defun doxymacs-file-comment ()
  (let ((fname (if (buffer-file-name) 
		   (file-name-nondirectory (buffer-file-name))
		 "")))
	(if (equal doxymacs-doxygen-style "JavaDoc")
	    (cons
	     (format (concat "/**\n"
			     " * @file   %s\n"
			     " * @author %s <%s>\n"
			     " * @date   %s\n"
			     " *\n"
			     " * @brief  \n"
			     " *\n"
			     " *\n"
			     " */")
		     fname
		     (user-full-name)
		     (user-mail-address)
		     (current-time-string))
	     6)
	  (cons
	   (format (concat "/*!\n"
			   " \\file   %s\n"
			   " \\author %s <%s>\n"
			   " \\date   %s\n"
			   " \n"
			   " \\brief  \n"
			   " \n"
			   " \n"
			   "*/")
		   fname
		   (user-full-name)
		   (user-mail-address)
		   (current-time-string))
	   6))))

(defun doxymacs-insert-file-comment ()
  "Inserts doxygen documentation for the current file at current point"
  (interactive "*")
  (let ((comment (doxymacs-file-comment)))
    (save-excursion
      (let ((start (point)))
	(insert (car comment))
	(let ((end (point)))
	  (indent-region start end nil))))
    (end-of-line (cdr comment))))


(defun doxymacs-extract-args-list (args-string)
  "Extracts the arguments from the given list (given as a string)"
  (save-excursion
    (if (equal args-string "")
	nil
      (doxymacs-extract-args-list-helper (split-string args-string ",")))))

(defun doxymacs-extract-args-list-helper (args-list)
  "Recursively get names of arguments"
  (save-excursion
    (if (eq args-list nil)
	nil
      (if (string-match 
	   (concat
	    "\\([a-zA-Z0-9_]+\\)\\s-*" ; arg name
	    "\\(\\[\\s-*[a-zA-Z0-9_]*\\s-*\\]\\)*" ; optional array bounds
	    "\\(=\\s-*.+\\s-*\\)?" ;optional assignment
	    "\\s-*$" ; end
	    )
	   (car args-list))
	  (cons
	   (substring (car args-list) (match-beginning 1) (match-end 1))
	   (doxymacs-extract-args-list-helper (cdr args-list)))
	(cons
	 (car args-list)
	 (doxymacs-extract-args-list-helper (cdr args-list)))))))


;; FIXME
;; This gets confused by the following examples:
;; - void qsort(int (*comp)(void *, void *), int left, int right);
;; - int f(int (*daytab)[5], int x);
;; - Anything that doesn't declare its return value
;; NOTE
;; - It doesn't really matter if the function name is incorrect... the 
;;   important bits are the arguments and the return value... those need
;;   to be correct for sure.
(defun doxymacs-find-next-func ()
  "Returns a list describing next function declaration, or nil if not found"
  (interactive)
  (save-excursion    
    (if (re-search-forward
	 (concat 
	  ;;I stole the following from func-menu.el
	  "\\(\\(template\\s-+<[^>]+>\\s-+\\)?"   ; template formals
	  "\\([a-zA-Z0-9_*&<,>:]+\\s-+\\)?"       ; type specs
	  "\\([a-zA-Z0-9_*&<,>\"]+\\s-+\\)?"
	  "\\([a-zA-Z0-9_*&<,>]+\\)\\s-+\\)"      ; return type
	  "\\(\\([a-zA-Z0-9_&~:<,>*]\\|\\(\\s +::\\s +\\)\\)+\\)"
	  "\\(o?perator\\s *.[^(]*\\)?\\(\\s-\\|\n\\)*(" ; name
	  "\\([^)]*\\))" ; arg list
	  ) nil t)
	(list (cons 'func (buffer-substring (match-beginning 6)
					    (match-end 6)))
	      (save-match-data 
		(cons 'args (doxymacs-extract-args-list
			     (buffer-substring (match-beginning 11)
					       (match-end 11)))))
	      (cons 'return (buffer-substring (match-beginning 5)
					      (match-end 5))))
      nil)))

(defun doxymacs-parm-comment (parms)
  "Inserts doxygen documentation for the given parms"
  (if (equal parms nil)
      ""
    (if (equal doxymacs-doxygen-style "JavaDoc")
	(concat " * @param " (car parms) "\t\n"
		(doxymacs-parm-comment (cdr parms)))
      (concat "  \\param " (car parms) "\t\n"
	      (doxymacs-parm-comment (cdr parms))))))

(defun doxymacs-func-comment (func)
  "Inserts doxygen documentation for the given func"
  (if (equal doxymacs-doxygen-style "JavaDoc")
      (cons
       (concat "/**\n"
	       " * \n"
	       " * \n"
	       (doxymacs-parm-comment (cdr (assoc 'args func)))
	       (unless (equal (cdr (assoc 'return func)) "void")
		 " * @return \n")
	       " */")
       2)
    (cons
     (concat "//! \n"
	     "/*!\n"
	     " \n"
	     (doxymacs-parm-comment (cdr (assoc 'args func)))
	     (unless (equal (cdr (assoc 'return func)) "void")
	       "  \\return \n")
	     " */")
     1)))

(defun doxymacs-insert-function-comment ()
  "Inserts doxygen documentation for the next function declaration at 
current point"
  (interactive "*")  
  (let ((num-lines 1))
    (save-excursion
      (widen)
      (let ((start (point))
	    (next-func (doxymacs-find-next-func)))
	(if (not (equal next-func nil))
	    (let ((comment (doxymacs-func-comment next-func)))
	      (insert (car comment))
	      (setq num-lines (cdr comment)))
	  (beep))
	(let ((end (point)))
	  (indent-region start end nil))))
    (end-of-line num-lines)))


;; Default key bindings

;; FIXME finish this.  What would be good keys for inserting documentation?

(defun doxymacs-default-key-bindings ()
  "Install default key bindings for doxymacs"
  (interactive)
  (global-set-key [(control ??)] 'doxymacs-lookup))


;; doxymacs.el ends here