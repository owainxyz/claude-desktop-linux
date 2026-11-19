use napi::{Error, Result, Status};
use napi_derive::napi;
use rustix::fd::{AsFd, BorrowedFd, IntoRawFd, OwnedFd};
use rustix::fs::{
    linkat, mkdirat, openat2, renameat, renameat_with, statx, unlinkat, AtFlags, Dir, FileType, Mode, OFlags,
    RenameFlags, ResolveFlags, Statx, StatxFlags,
};
use rustix::io::Errno;

const RESOLVE: ResolveFlags = ResolveFlags::BENEATH
    .union(ResolveFlags::NO_SYMLINKS)
    .union(ResolveFlags::NO_MAGICLINKS);

fn code(e: Errno) -> &'static str {
    match e {
        Errno::NOENT => "ENOENT",
        Errno::EXIST => "EEXIST",
        Errno::NOTDIR => "ENOTDIR",
        Errno::ISDIR => "EISDIR",
        Errno::LOOP => "ELOOP",
        Errno::XDEV => "EXDEV",
        Errno::ACCESS => "EACCES",
        Errno::PERM => "EPERM",
        Errno::NOTEMPTY => "ENOTEMPTY",
        Errno::BUSY => "EBUSY",
        Errno::INVAL => "EINVAL",
        Errno::MLINK => "EMLINK",
        Errno::BADF => "EBADF",
        Errno::NAMETOOLONG => "ENAMETOOLONG",
        Errno::ROFS => "EROFS",
        Errno::NOSPC => "ENOSPC",
        Errno::MFILE => "EMFILE",
        Errno::NFILE => "ENFILE",
        Errno::AGAIN => "EAGAIN",
        Errno::NOSYS => "ENOSYS",
        Errno::IO => "EIO",
        Errno::TXTBSY => "ETXTBSY",
        Errno::DQUOT => "EDQUOT",
        _ => "EUNKNOWN",
    }
}

fn os(e: Errno, what: &str) -> Error {
    Error::new(Status::GenericFailure, format!("{}: {} ({})", code(e), what, e.raw_os_error()))
}

fn fail(c: &str, msg: &str) -> Error {
    Error::new(Status::GenericFailure, format!("{c}: {msg}"))
}

const MAX_SEGS: usize = 1024;

fn check(segs: &[String]) -> Result<()> {
    if segs.len() > MAX_SEGS {
        return Err(fail("ENAMETOOLONG", "path too deep"));
    }
    for s in segs {
        if s.is_empty() || s == "." || s == ".." || s.contains('/') || s.contains('\0') {
            return Err(fail("EXDEV", &format!("segment escapes root: {s:?}")));
        }
    }
    Ok(())
}

fn borrow(fd: i32) -> Result<BorrowedFd<'static>> {
    if fd < 0 {
        return Err(fail("EBADF", &format!("bad file descriptor {fd}")));
    }
    Ok(unsafe { BorrowedFd::borrow_raw(fd) })
}

fn open_dir(dir: i32, segs: &[String], flags: OFlags) -> Result<Option<OwnedFd>> {
    if segs.is_empty() {
        return Ok(None);
    }
    let p = segs.join("/");
    openat2(borrow(dir)?, p.as_str(), flags | OFlags::DIRECTORY | OFlags::CLOEXEC, Mode::empty(), RESOLVE)
        .map(Some)
        .map_err(|e| os(e, &p))
}

fn with_parent<T>(dir: i32, segs: &[String], f: impl FnOnce(BorrowedFd, &str) -> Result<T>) -> Result<T> {
    check(segs)?;
    let (leaf, parents) = segs.split_last().ok_or_else(|| fail("EINVAL", "empty path beneath root"))?;
    let owned = open_dir(dir, parents, OFlags::PATH)?;
    let fd = match &owned {
        Some(o) => o.as_fd(),
        None => borrow(dir)?,
    };
    f(fd, leaf)
}

fn stx(fd: BorrowedFd, name: &str, flags: AtFlags) -> Result<Statx> {
    statx(fd, name, flags, StatxFlags::BASIC_STATS | StatxFlags::BTIME).map_err(|e| os(e, name))
}

fn leaf_stat(dir: i32, segs: &[String]) -> Result<Statx> {
    if segs.is_empty() {
        return stx(borrow(dir)?, "", AtFlags::EMPTY_PATH);
    }
    with_parent(dir, segs, |p, leaf| stx(p, leaf, AtFlags::SYMLINK_NOFOLLOW))
}

fn mode_type(m: u16) -> FileType {
    FileType::from_raw_mode(m as u32)
}

#[napi(object)]
pub struct RawStat {
    pub dev: f64,
    pub ino: f64,
    pub mode: f64,
    pub nlink: f64,
    pub uid: f64,
    pub gid: f64,
    pub rdev: f64,
    pub size: f64,
    pub blksize: f64,
    pub blocks: f64,
    pub atime_sec: f64,
    pub atime_nsec: f64,
    pub mtime_sec: f64,
    pub mtime_nsec: f64,
    pub ctime_sec: f64,
    pub ctime_nsec: f64,
    pub birthtime_sec: f64,
    pub birthtime_nsec: f64,
}

fn raw(s: &Statx) -> RawStat {
    let dev = |maj: u32, min: u32| rustix::fs::makedev(maj, min) as f64;
    RawStat {
        dev: dev(s.stx_dev_major, s.stx_dev_minor),
        ino: s.stx_ino as f64,
        mode: s.stx_mode as f64,
        nlink: s.stx_nlink as f64,
        uid: s.stx_uid as f64,
        gid: s.stx_gid as f64,
        rdev: dev(s.stx_rdev_major, s.stx_rdev_minor),
        size: s.stx_size as f64,
        blksize: s.stx_blksize as f64,
        blocks: s.stx_blocks as f64,
        atime_sec: s.stx_atime.tv_sec as f64,
        atime_nsec: s.stx_atime.tv_nsec as f64,
        mtime_sec: s.stx_mtime.tv_sec as f64,
        mtime_nsec: s.stx_mtime.tv_nsec as f64,
        ctime_sec: s.stx_ctime.tv_sec as f64,
        ctime_nsec: s.stx_ctime.tv_nsec as f64,
        birthtime_sec: s.stx_btime.tv_sec as f64,
        birthtime_nsec: s.stx_btime.tv_nsec as f64,
    }
}

#[napi(object)]
pub struct StatHandle {
    pub fd: i32,
    pub is_symbolic_link: bool,
}

#[napi(object)]
pub struct DirEntry {
    pub name: String,
    pub is_file: bool,
    pub is_directory: bool,
    pub is_symbolic_link: bool,
    pub is_block_device: bool,
    pub is_character_device: bool,
    #[napi(js_name = "isFIFO")]
    pub is_fifo: bool,
    pub is_socket: bool,
}

#[napi(object)]
pub struct DirListing {
    pub entries: Vec<DirEntry>,
    pub truncated: bool,
}

async fn blocking<T: Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<T> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| Error::new(Status::GenericFailure, format!("EUNKNOWN: {e}")))?
}

fn open_root(path: &str) -> Result<i32> {
    rustix::fs::open(path, OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC, Mode::empty())
        .map(|f| f.into_raw_fd())
        .map_err(|e| os(e, path))
}

#[napi]
pub async fn open_root_dir(path: String) -> Result<i32> {
    blocking(move || open_root(&path)).await
}

#[napi]
pub fn open_root_dir_sync(path: String) -> Result<i32> {
    open_root(&path)
}

#[napi]
pub async fn open_beneath(dir_fd: i32, segs: Vec<String>, flags: i32, mode: u32) -> Result<i32> {
    blocking(move || {
        check(&segs)?;
        let fl = OFlags::from_bits_retain(flags as u32) | OFlags::NOFOLLOW | OFlags::CLOEXEC;
        let p = if segs.is_empty() { ".".to_string() } else { segs.join("/") };
        openat2(borrow(dir_fd)?, p.as_str(), fl, Mode::from_bits_truncate(mode), RESOLVE)
            .map(|f| f.into_raw_fd())
            .map_err(|e| os(e, &p))
    })
    .await
}

#[napi]
pub async fn stat_handle_beneath(dir_fd: i32, segs: Vec<String>) -> Result<StatHandle> {
    blocking(move || {
        check(&segs)?;
        let p = if segs.is_empty() { ".".to_string() } else { segs.join("/") };
        let fd = openat2(borrow(dir_fd)?, p.as_str(), OFlags::PATH | OFlags::NOFOLLOW | OFlags::CLOEXEC, Mode::empty(), RESOLVE)
            .map_err(|e| os(e, &p))?;
        let s = stx(fd.as_fd(), "", AtFlags::EMPTY_PATH)?;
        Ok(StatHandle { is_symbolic_link: mode_type(s.stx_mode) == FileType::Symlink, fd: fd.into_raw_fd() })
    })
    .await
}

#[napi]
pub async fn verify_leaf_beneath(dir_fd: i32, segs: Vec<String>, fd: i32) -> Result<()> {
    blocking(move || {
        let h = stx(borrow(fd)?, "", AtFlags::EMPTY_PATH)?;
        if mode_type(h.stx_mode) != FileType::RegularFile || h.stx_nlink == 0 {
            return Ok(());
        }
        if h.stx_nlink > 1 {
            return Err(fail("EMLINK", &format!("handle-links:{}", h.stx_nlink)));
        }
        let n = match leaf_stat(dir_fd, &segs) {
            Ok(n) => n,
            Err(e) if e.reason.starts_with("ENOENT") || e.reason.starts_with("ENOTDIR") => {
                return Err(fail("EMLINK", "name-gone"))
            }
            Err(e) => return Err(e),
        };
        if mode_type(n.stx_mode) != FileType::RegularFile {
            return Err(fail("EMLINK", "name-not-regular"));
        }
        if (n.stx_dev_major, n.stx_dev_minor, n.stx_ino) != (h.stx_dev_major, h.stx_dev_minor, h.stx_ino) {
            return Err(fail("EMLINK", "name-other"));
        }
        if n.stx_nlink != 1 {
            let why = if n.stx_nlink == 0 { "name-gone".to_string() } else { format!("name-links:{}", n.stx_nlink) };
            return Err(fail("EMLINK", &why));
        }
        Ok(())
    })
    .await
}

#[napi]
pub async fn lstat_beneath(dir_fd: i32, segs: Vec<String>) -> Result<RawStat> {
    blocking(move || leaf_stat(dir_fd, &segs).map(|s| raw(&s))).await
}

#[napi]
pub async fn stat_beneath(dir_fd: i32, segs: Vec<String>) -> Result<RawStat> {
    blocking(move || {
        let s = leaf_stat(dir_fd, &segs)?;
        if mode_type(s.stx_mode) == FileType::Symlink {
            return Err(fail("ELOOP", "symlink beneath root"));
        }
        Ok(raw(&s))
    })
    .await
}

#[napi]
pub async fn mkdir_beneath(dir_fd: i32, segs: Vec<String>, mode: u32) -> Result<()> {
    blocking(move || {
        with_parent(dir_fd, &segs, |p, leaf| mkdirat(p, leaf, Mode::from_bits_truncate(mode)).map_err(|e| os(e, leaf)))
    })
    .await
}

#[napi]
pub async fn readdir_beneath(dir_fd: i32, segs: Vec<String>, max: Option<u32>) -> Result<DirListing> {
    blocking(move || {
        check(&segs)?;
        let owned = open_dir(dir_fd, &segs, OFlags::RDONLY)?;
        let fd = match &owned {
            Some(o) => o.as_fd(),
            None => borrow(dir_fd)?,
        };
        let mut dir = Dir::read_from(fd).map_err(|e| os(e, "readdir"))?;
        let mut entries = Vec::new();
        let mut truncated = false;
        while let Some(ent) = dir.read() {
            let ent = ent.map_err(|e| os(e, "readdir"))?;
            let name = ent.file_name().to_string_lossy().into_owned();
            if name == "." || name == ".." {
                continue;
            }
            if let Some(m) = max {
                if entries.len() as u32 >= m {
                    truncated = true;
                    break;
                }
            }
            let mut t = ent.file_type();
            if t == FileType::Unknown {
                if let Ok(s) = stx(fd, &name, AtFlags::SYMLINK_NOFOLLOW) {
                    t = mode_type(s.stx_mode);
                }
            }
            entries.push(DirEntry {
                name,
                is_file: t == FileType::RegularFile,
                is_directory: t == FileType::Directory,
                is_symbolic_link: t == FileType::Symlink,
                is_block_device: t == FileType::BlockDevice,
                is_character_device: t == FileType::CharacterDevice,
                is_fifo: t == FileType::Fifo,
                is_socket: t == FileType::Socket,
            });
        }
        Ok(DirListing { entries, truncated })
    })
    .await
}

fn two(dir: i32, a: &[String], b: &[String], f: impl FnOnce(BorrowedFd, &str, BorrowedFd, &str) -> Result<()>) -> Result<()> {
    with_parent(dir, a, |pa, la| with_parent(dir, b, |pb, lb| f(pa, la, pb, lb)))
}

#[napi]
pub async fn rename_beneath(dir_fd: i32, from: Vec<String>, to: Vec<String>) -> Result<()> {
    blocking(move || two(dir_fd, &from, &to, |pa, la, pb, lb| renameat(pa, la, pb, lb).map_err(|e| os(e, lb)))).await
}

fn no_replace(dir: i32, from: &[String], to: &[String]) -> Result<()> {
    two(dir, from, to, |pa, la, pb, lb| {
        renameat_with(pa, la, pb, lb, RenameFlags::NOREPLACE).map_err(|e| os(e, lb))
    })
}

#[napi]
pub async fn rename_beneath_onto_free_name(dir_fd: i32, from: Vec<String>, to: Vec<String>) -> Result<()> {
    blocking(move || no_replace(dir_fd, &from, &to)).await
}

#[napi]
pub fn rename_beneath_onto_free_name_sync(dir_fd: i32, from: Vec<String>, to: Vec<String>) -> Result<()> {
    no_replace(dir_fd, &from, &to)
}

#[napi]
pub async fn link_beneath(dir_fd: i32, from: Vec<String>, to: Vec<String>) -> Result<()> {
    blocking(move || {
        two(dir_fd, &from, &to, |pa, la, pb, lb| linkat(pa, la, pb, lb, AtFlags::empty()).map_err(|e| os(e, lb)))
    })
    .await
}

#[napi]
pub async fn unlink_beneath(dir_fd: i32, segs: Vec<String>) -> Result<()> {
    blocking(move || with_parent(dir_fd, &segs, |p, leaf| unlinkat(p, leaf, AtFlags::empty()).map_err(|e| os(e, leaf))))
        .await
}

#[napi]
pub async fn rmdir_beneath(dir_fd: i32, segs: Vec<String>) -> Result<()> {
    blocking(move || {
        with_parent(dir_fd, &segs, |p, leaf| unlinkat(p, leaf, AtFlags::REMOVEDIR).map_err(|e| os(e, leaf)))
    })
    .await
}

#[napi]
pub fn awake_milliseconds() -> f64 {
    let t = rustix::time::clock_gettime(rustix::time::ClockId::Monotonic);
    t.tv_sec as f64 * 1000.0 + t.tv_nsec as f64 / 1e6
}
