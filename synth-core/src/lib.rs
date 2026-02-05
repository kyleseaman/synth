use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::fs::File;
use std::io::Read;
use std::process::{Command, Stdio};
use docx_rs::*;

/// Extract plain text from a .docx file
#[no_mangle]
pub extern "C" fn extract_text(path: *const c_char) -> *mut c_char {
    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut file = match File::open(path_str) {
        Ok(f) => f,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut buf = Vec::new();
    if file.read_to_end(&mut buf).is_err() {
        return std::ptr::null_mut();
    }

    let doc = match read_docx(&buf) {
        Ok(d) => d,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut text = String::new();
    for child in doc.document.children {
        if let DocumentChild::Paragraph(p) = child {
            for pc in p.children {
                if let ParagraphChild::Run(r) = pc {
                    for rc in r.children {
                        if let RunChild::Text(t) = rc {
                            text.push_str(&t.text);
                        }
                    }
                }
            }
            text.push('\n');
        }
    }

    CString::new(text).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}


/// Send a prompt to kiro-cli and get the response
#[no_mangle]
pub extern "C" fn kiro_chat(prompt: *const c_char) -> *mut c_char {
    let c_str = unsafe { CStr::from_ptr(prompt) };
    let prompt_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let output = Command::new("kiro-cli")
        .args(["chat", "--no-interactive", "-a", prompt_str])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();

    match output {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout);
            let cleaned = strip_ansi(&stdout);
            CString::new(cleaned).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
        }
        Err(_) => std::ptr::null_mut(),
    }
}

fn strip_ansi(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&nc) = chars.peek() {
                    chars.next();
                    if nc.is_ascii_alphabetic() { break; }
                }
            }
        } else {
            result.push(c);
        }
    }
    result
}
