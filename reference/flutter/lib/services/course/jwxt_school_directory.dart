import 'package:pinyin/pinyin.dart';
import 'jwxt_system_family.dart';

part 'jwxt_school_entries.dart';
part 'jwxt_school_spellings.dart';
part 'jwxt_school_ranking.dart';

/// 可搜索的高校教务目录。
///
/// 目录只保存公开的学校名称、别名和常见教务系统家族，不保存账号、密码
/// 或登录 cookie。学校入口可能因校区、年份和网络环境变化，未固定入口的
/// 学校仍需用户粘贴本校官方教务地址。
class JwxtSchoolProfile {
  bool get preferDesktop =>
      adapterId == 'whu-graduate' ||
      id == 'hfut-graduate' ||
      id == 'nuaa-graduate';
  const JwxtSchoolProfile({
    required this.id,
    required this.name,
    required String adapterId,
    this.aliases = const <String>[],
    this.loginUrl,
    this.timetableUrl,
    this.sourceUrl,
    this.entryNote,
    this.alternativeUrls = const [],
    this.educationLevel = '未标注',
    this.entryStatus,
    this.authenticatedImportVerified = false,
    this.userReportedCapture = false,
  }) : _adapterId = adapterId;

  final String id;
  final String name;
  final String _adapterId;
  String get adapterId => _adapterId == 'whu-graduate'
      ? _adapterId
      : knownJwxtSystemFamily(loginUrl ?? '') ?? _adapterId;
  final List<String> aliases;
  final String? loginUrl;
  final String? timetableUrl;
  final String? sourceUrl;
  final String? entryNote;
  final List<String> alternativeUrls;
  final String educationLevel;
  final String? entryStatus;
  final bool authenticatedImportVerified;
  final bool userReportedCapture;

  String get entryStatusLabel {
    final status = authenticatedImportVerified
        ? '真实课表导入已验收'
        : userReportedCapture
            ? '用户实测抓取成功 · 请核对完整学期'
            : switch (entryStatus) {
                'login-form-visible' => '登录页已检查 · 课表数据待验收',
                'sso-or-login-link-visible' => '认证入口已检查 · 课表数据待验收',
                'page-without-login-evidence' => '网页可达 · 登录入口待确认',
                'android-cleartext-blocked' => '明文 HTTP 已拦截 · 请使用官方 HTTPS 入口',
                'official-entry-not-confirmed' => '错误旧入口已隔离 · 请填写学校官方教务地址',
                'verification-or-access-block' => '被验证或访问策略拦截',
                'login-form-hidden' => '仅发现隐藏登录表单 · 待人工核对',
                'http-error' ||
                'navigation-error' ||
                'request-error' =>
                  '历史入口探测未通过 · 仍可打开尝试',
                _ => '入口收录 · 尚未验证真实课表导入',
              };
    return educationLevel == '未标注' ? status : '$educationLevel · $status';
  }

  String get searchableText =>
      <String>[name, ...aliases].join(' ').toLowerCase();

  String get adapterLabel => switch (adapterId) {
        'zjw' => '正方',
        'qz' => '强智',
        'qg' => '青果',
        'urp' => 'URP',
        'wisedu' => '金智',
        'whu-graduate' => '研究生综合服务平台',
        'nanruan' => '南软',
        'chaoxing' => '超星',
        'eams' => '树维 / EAMS',
        _ => '通用表格',
      };
}

/// 首批内置目录覆盖常见地区与教务生态；新学校可通过同一套目录格式追加，
/// 不需要修改课程页或 WebView 页面。
const _baseSchoolDirectory = <JwxtSchoolProfile>[
  JwxtSchoolProfile(
    id: 'whu-graduate',
    name: '武汉大学研究生',
    aliases: ['武汉大学', 'WHU', '武大'],
    adapterId: 'whu-graduate',
    loginUrl: 'http://newyjs.whu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do',
    userReportedCapture: true,
    entryNote: '用户于 2026-10-21 反馈：研究生课表已实测抓取成功。专用解析保留星期属性及逐节周次合并；导入时仍请核对完整学期。',
  ),
  JwxtSchoolProfile(
      id: 'hust', name: '华中科技大学', aliases: ['华科', 'HUST'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'wuhan-tech',
      name: '武汉理工大学',
      aliases: ['武理', 'WHUT'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ccnu', name: '华中师范大学', aliases: ['华师', 'CCNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'whu-arts', name: '武汉音乐学院', aliases: ['WHCM'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'pku', name: '北京大学', aliases: ['北大', 'PKU'], adapterId: 'urp'),
  JwxtSchoolProfile(
    id: 'tsinghua',
    name: '清华大学',
    aliases: ['清华', 'THU'],
    adapterId: 'urp',
    // 清华公开资料给出的学生信息门户入口；登录后在“教学”中进入本学期课程。
    loginUrl: 'https://info.tsinghua.edu.cn/',
  ),
  JwxtSchoolProfile(
      id: 'ruc', name: '中国人民大学', aliases: ['人大', 'RUC'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'bnu', name: '北京师范大学', aliases: ['北师大', 'BNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
    id: 'bit',
    name: '北京理工大学',
    aliases: ['北理工', 'BIT'],
    adapterId: 'wisedu',
    loginUrl: 'https://jxzxehall.bit.edu.cn',
    sourceUrl:
        'https://jxzx.bit.edu.cn/jxyx/xkgl/2427d8ac69bb479fafb6b30b518337d1.htm',
    entryNote: '2026 年官方通知指向本硕博一体化教学系统；登录后的课程表读取尚未验证。',
  ),
  JwxtSchoolProfile(
      id: 'cau', name: '中国农业大学', aliases: ['农大', 'CAU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'nankai', name: '南开大学', aliases: ['NKU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'tju', name: '天津大学', aliases: ['天大', 'TJU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'sjtu', name: '上海交通大学', aliases: ['上交', 'SJTU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'fudan', name: '复旦大学', aliases: ['FDU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'tongji', name: '同济大学', aliases: ['Tongji'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'zju', name: '浙江大学', aliases: ['浙大', 'ZJU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'nju', name: '南京大学', aliases: ['南大', 'NJU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'seu', name: '东南大学', aliases: ['东大', 'SEU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ustc', name: '中国科学技术大学', aliases: ['中科大', 'USTC'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xmu', name: '厦门大学', aliases: ['厦大', 'XMU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'scu', name: '四川大学', aliases: ['川大', 'SCU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'uestc',
      name: '电子科技大学',
      aliases: ['电子科大', 'UESTC'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xjtu', name: '西安交通大学', aliases: ['西交', 'XJTU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'nwpu', name: '西北工业大学', aliases: ['西工大', 'NWPU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hit', name: '哈尔滨工业大学', aliases: ['哈工大', 'HIT'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'jlu', name: '吉林大学', aliases: ['吉大', 'JLU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'sdu', name: '山东大学', aliases: ['山大', 'SDU'], adapterId: 'zjw'),
  JwxtSchoolProfile(id: 'csu', name: '中南大学', aliases: ['CSU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'hnu', name: '湖南大学', aliases: ['湖大', 'HNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
    id: 'sysu',
    name: '中山大学',
    aliases: ['中大', 'SYSU'],
    adapterId: 'generic',
    loginUrl: 'https://jwxt.sysu.edu.cn',
    sourceUrl: 'https://seit.sysu.edu.cn/article/3066',
    entryNote: '2026 年官方通知指向 HTTPS 根入口；登录后的课表读取尚未验证。',
  ),
  JwxtSchoolProfile(
      id: 'jnu', name: '暨南大学', aliases: ['暨大', 'JNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'scau', name: '华南农业大学', aliases: ['华农', 'SCAU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'xidian', name: '西安电子科技大学', aliases: ['西电', 'XDU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'dlut', name: '大连理工大学', aliases: ['大工', 'DLUT'], adapterId: 'zjw'),
  // 华北 / 东北
  JwxtSchoolProfile(
      id: 'buaa', name: '北京航空航天大学', aliases: ['北航', 'BUAA'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'bjtu', name: '北京交通大学', aliases: ['北交', 'BJTU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ustb', name: '北京科技大学', aliases: ['北科大', 'USTB'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'bupt', name: '北京邮电大学', aliases: ['北邮', 'BUPT'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'cupb',
      name: '中国石油大学（北京）',
      aliases: ['石大北京', 'CUPB'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'cufe', name: '中央财经大学', aliases: ['央财', 'CUFE'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'uibe', name: '对外经济贸易大学', aliases: ['贸大', 'UIBE'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'cupl', name: '中国政法大学', aliases: ['法大', 'CUPL'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'bfsu', name: '北京外国语大学', aliases: ['北外', 'BFSU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'blcu', name: '北京语言大学', aliases: ['北语', 'BLCU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'bucm', name: '北京中医药大学', aliases: ['北中医', 'BUCM'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ncepu', name: '华北电力大学', aliases: ['华电', 'NCEPU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'bfu', name: '北京林业大学', aliases: ['北林', 'BFU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'cuc', name: '中国传媒大学', aliases: ['中传', 'CUC'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'buct', name: '北京化工大学', aliases: ['北化', 'BUCT'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'tjnu', name: '天津师范大学', aliases: ['天师', 'TJNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'tust', name: '天津科技大学', aliases: ['天科大', 'TUST'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'tmu', name: '天津医科大学', aliases: ['天医', 'TMU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'hebu', name: '河北大学', aliases: ['河大', 'HEBU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ysu', name: '燕山大学', aliases: ['燕大', 'YSU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hebut',
      name: '河北工业大学',
      aliases: ['河北工大', 'HEBUT'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
    id: 'neu',
    name: '东北大学',
    aliases: ['东大', 'NEU'],
    adapterId: 'generic',
    loginUrl: 'https://jwxt.neu.edu.cn/',
    alternativeUrls: ['https://personal.neu.edu.cn'],
    sourceUrl: 'https://aao.neu.edu.cn/2026/0227/c9405a450413/page.htm',
    entryNote: '教务系统官方说明仅限校园网或学校 VPN；一号通门户也是官方入口，不会绕过网络限制。',
  ),
  JwxtSchoolProfile(
      id: 'heu', name: '哈尔滨工程大学', aliases: ['哈工程', 'HEU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'nefu', name: '东北林业大学', aliases: ['东北林大', 'NEFU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hlju', name: '黑龙江大学', aliases: ['黑大', 'HLJU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'dlu-univ', name: '大连大学', aliases: ['DLU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'dufe', name: '东北财经大学', aliases: ['东财', 'DUFE'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'neau', name: '东北农业大学', aliases: ['东北农大', 'NEAU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'nenu', name: '东北师范大学', aliases: ['东北师大', 'NENU'], adapterId: 'urp'),
  // 华东
  JwxtSchoolProfile(
      id: 'ecnu', name: '华东师范大学', aliases: ['华师大', 'ECNU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'shu', name: '上海大学', aliases: ['上大', 'SHU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'shnu', name: '上海师范大学', aliases: ['上师大', 'SHNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'usst', name: '上海理工大学', aliases: ['上理工', 'USST'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'shou',
      name: '上海海洋大学',
      aliases: ['上海大', 'SHOU'],
      adapterId: 'generic'),
  JwxtSchoolProfile(
      id: 'suda', name: '苏州大学', aliases: ['苏大', 'Soochow'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hhu', name: '河海大学', aliases: ['河海', 'HHU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'nuaa', name: '南京航空航天大学', aliases: ['南航', 'NUAA'], adapterId: 'eams'),
  JwxtSchoolProfile(
    id: 'nuaa-graduate',
    name: '南京航空航天大学研究生',
    aliases: ['南航研究生', '南航研', 'NHYJS', 'NUAA Graduate'],
    adapterId: 'nanruan',
    loginUrl: 'https://graduate.nuaa.edu.cn/gmis5/home/stulogin',
    sourceUrl: 'https://xxhc.nuaa.edu.cn/17987/list.htm',
    educationLevel: '研究生',
    entryStatus: 'login-form-visible',
    entryNote:
        '学校官方研究生 GMIS 5 学生入口。支持统一认证与独立登录；进入本学期完整课表后读取，保留弹出窗口及桌面网页。公开登录页已核对，真实账号整学期导入待验收。',
  ),
  JwxtSchoolProfile(
      id: 'njust', name: '南京理工大学', aliases: ['南理工', 'NJUST'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'nnu', name: '南京师范大学', aliases: ['南师大', 'NNU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'yangzhou', name: '扬州大学', aliases: ['扬大', 'YZU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'jsu', name: '江苏大学', aliases: ['江大', 'JSU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'nbu', name: '宁波大学', aliases: ['宁大', 'NBU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hdu', name: '杭州电子科技大学', aliases: ['杭电', 'HDU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'zjsu', name: '浙江工商大学', aliases: ['浙商大', 'ZJSU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'hfut',
      name: '合肥工业大学',
      aliases: ['合工大', 'HFUT', '合肥工业大学本科'],
      adapterId: 'eams',
      loginUrl: 'https://jxglstu.hfut.edu.cn/eams5-student/login',
      sourceUrl: 'https://jxglstu.hfut.edu.cn/eams5-student/login',
      entryNote: '本科 · 树维 EAMS5；登录后进入个人课表并选择整个学期。'),
  JwxtSchoolProfile(
      id: 'hfut-graduate',
      name: '合肥工业大学研究生',
      aliases: ['合工大研究生', 'HFUT'],
      adapterId: 'nanruan',
      loginUrl: 'https://gmsstu.hfut.edu.cn/logon',
      alternativeUrls: ['https://gmsstu.hfut.edu.cn/'],
      sourceUrl: 'https://pyb.hfut.edu.cn/info/1006/1062.htm',
      entryNote:
          '研究生 · 南软6.0学生直登；登录后打开本学期完整课表。若学校限制校外访问，请使用校园网或学校官方VPN；统一认证保留为备用入口。'),
  JwxtSchoolProfile(
      id: 'ahu', name: '安徽大学', aliases: ['安大', 'AHU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ahnu', name: '安徽师范大学', aliases: ['安师大', 'AHNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'fzu', name: '福州大学', aliases: ['福大', 'FZU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'fjnu', name: '福建师范大学', aliases: ['福建师大', 'FJNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'hqu', name: '华侨大学', aliases: ['华大', 'HQU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ncu', name: '南昌大学', aliases: ['昌大', 'NCU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'jxnu', name: '江西师范大学', aliases: ['江西师大', 'JXNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'ecjtu',
      name: '华东交通大学',
      aliases: ['华东交大', 'ECJTU'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ouc', name: '中国海洋大学', aliases: ['海大', 'OUC'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'cupqd',
      name: '中国石油大学（华东）',
      aliases: ['石大华东', 'CUPQ'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'qdu', name: '青岛大学', aliases: ['青大', 'QDU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ytu', name: '烟台大学', aliases: ['烟大', 'YTU'], adapterId: 'qz'),
  // 华中 / 华南
  JwxtSchoolProfile(
    id: 'whu',
    name: '武汉大学',
    aliases: ['武大本科', 'WHU'],
    adapterId: 'generic',
    loginUrl: 'https://jwgl.whu.edu.cn/xtgl/login_slogin.html',
    timetableUrl: 'https://jwgl.whu.edu.cn/kbcx/xskbcx_cxXskbcxIndex.html',
  ),
  JwxtSchoolProfile(
      id: 'hubu', name: '湖北大学', aliases: ['湖大', 'HUBU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'wust', name: '武汉科技大学', aliases: ['武科大', 'WUST'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hbut', name: '湖北工业大学', aliases: ['湖工大', 'HBUT'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'zuel',
      name: '中南财经政法大学',
      aliases: ['中南财大', 'ZUEL'],
      adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'hue', name: '湖北经济学院', aliases: ['湖经', 'HUE'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'wtu', name: '武汉纺织大学', aliases: ['武纺', 'WTU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hunnu',
      name: '湖南师范大学',
      aliases: ['湖南师大', 'HUNNU'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'hunau', name: '湖南农业大学', aliases: ['湖南农大', 'HUNAU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'csust', name: '长沙理工大学', aliases: ['长理', 'CSUST'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xtu', name: '湘潭大学', aliases: ['湘大', 'XTU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'scut', name: '华南理工大学', aliases: ['华工', 'SCUT'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'scnu', name: '华南师范大学', aliases: ['华师', 'SCNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'gdut', name: '广东工业大学', aliases: ['广工', 'GDUT'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'gzhu', name: '广州大学', aliases: ['广大', 'GZHU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'gdufs',
      name: '广东外语外贸大学',
      aliases: ['广外', 'GDUFS'],
      adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'szu', name: '深圳大学', aliases: ['深大', 'SZU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'gxu', name: '广西大学', aliases: ['广西农大', 'GXU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'gxnu', name: '广西师范大学', aliases: ['广西师大', 'GXNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'hainu', name: '海南大学', aliases: ['海大', 'HAINU'], adapterId: 'zjw'),
  // 西南 / 西北 / 边疆
  JwxtSchoolProfile(
      id: 'cqu', name: '重庆大学', aliases: ['重大', 'CQU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'swu', name: '西南大学', aliases: ['西大', 'SWU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'cqjtu', name: '重庆交通大学', aliases: ['重庆交大', 'CQJTU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'cqmu', name: '重庆医科大学', aliases: ['重医', 'CQMU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'swjtu',
      name: '西南交通大学',
      aliases: ['西南交大', 'SWJTU'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'swufe', name: '西南财经大学', aliases: ['西财', 'SWUFE'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'cdutcm',
      name: '成都中医药大学',
      aliases: ['成中医', 'CDUTCM'],
      adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'sicnu', name: '四川师范大学', aliases: ['川师', 'SICNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'swpu', name: '西南石油大学', aliases: ['西南石大', 'SWPU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'cuit', name: '成都信息工程大学', aliases: ['成信大', 'CUIT'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'ynu', name: '云南大学', aliases: ['云大', 'YNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'kust', name: '昆明理工大学', aliases: ['昆工', 'KUST'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'ynnu', name: '云南师范大学', aliases: ['云师大', 'YNNU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'nwuniv', name: '西北大学', aliases: ['西大', 'NWU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xauat',
      name: '西安建筑科技大学',
      aliases: ['西建大', 'XAUAT'],
      adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xaut', name: '西安理工大学', aliases: ['西理工', 'XAUT'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'nwnu', name: '西北师范大学', aliases: ['西北师大', 'NWNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'lzu', name: '兰州大学', aliases: ['兰大', 'LZU'], adapterId: 'urp'),
  JwxtSchoolProfile(
      id: 'lzjtu', name: '兰州交通大学', aliases: ['兰交大', 'LZJTU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'qhu', name: '青海大学', aliases: ['青大', 'QHU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'nxu', name: '宁夏大学', aliases: ['宁大', 'NXU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'tibet', name: '西藏大学', aliases: ['藏大', 'TUU'], adapterId: 'generic'),
  JwxtSchoolProfile(
      id: 'imu', name: '内蒙古大学', aliases: ['内大', 'IMU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'imau', name: '内蒙古农业大学', aliases: ['内农大', 'IMAU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'imnu', name: '内蒙古师范大学', aliases: ['内师大', 'IMNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xju', name: '新疆大学', aliases: ['新大', 'XJU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
    id: 'shzu',
    name: '石河子大学',
    aliases: ['石大', 'SHZU', '石河子大学本科'],
    adapterId: 'qz',
    loginUrl:
        'https://authserver.shzu.edu.cn/authserver/login?service=https%3A%2F%2Fjwgl.shzu.edu.cn%2Fsso.jsp',
    timetableUrl: 'https://jwgl.shzu.edu.cn/jsxsd/',
    alternativeUrls: ['https://jwgl.shzu.edu.cn/jsxsd/'],
    sourceUrl: 'https://jwc.shzu.edu.cn/',
    entryNote: '本科 · 学校官网统一认证；登录后打开个人完整课表。',
  ),
  JwxtSchoolProfile(
    id: 'shzu-graduate',
    name: '石河子大学研究生',
    aliases: ['石大研究生', 'SHZU'],
    adapterId: 'nanruan',
    loginUrl: 'http://gs.shzu.edu.cn/gmis5/home/login',
    alternativeUrls: ['http://gs.shzu.edu.cn/gmis5/student/default/index'],
    sourceUrl: 'https://yjsh.shzu.edu.cn/',
    entryNote: '研究生 · 官方研究生院入口；仍使用 HTTP，外网可能受限，先连接校园网或官方 VPN。',
  ),
  JwxtSchoolProfile(
      id: 'xjmu', name: '新疆医科大学', aliases: ['新医大', 'XJMU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'xjau', name: '新疆农业大学', aliases: ['新农大', 'XJAU'], adapterId: 'qz'),
  JwxtSchoolProfile(
      id: 'xjnu', name: '新疆师范大学', aliases: ['新疆师大', 'XJNU'], adapterId: 'zjw'),
  JwxtSchoolProfile(
      id: 'other',
      name: '其他高校',
      aliases: ['自定义学校', '未收录'],
      adapterId: 'generic'),
];

// Public entry metadata only. A directory entry never certifies a successful import.
final jwxtSchoolDirectory =
    List<JwxtSchoolProfile>.unmodifiable((<JwxtSchoolProfile>[
  for (final profile in _baseSchoolDirectory)
    if (profile.id != 'other') _withResearchedEntry(profile),
  for (final profile in _schoolEntryDirectory)
    if (!_baseSchoolDirectory.any((p) => p.name == profile.name)) profile,
  _baseSchoolDirectory.last,
]..sort(_compareSchools)));

// Cache each name once: typing in the picker must not repeatedly romanise 2,600 entries.
final _schoolSpellings = <String, String>{};
String _schoolSpelling(String name) => _schoolSpellings.putIfAbsent(name, () {
      final shipped = _precomputedSchoolSpellings77[name];
      if (shipped != null) return shipped;
      var text = PinyinHelper.getPinyinE(name,
          separator: ' ', defPinyin: '', format: PinyinFormat.WITHOUT_TONE);
      // These established place names need their geographic pronunciation.
      if (name.startsWith('重庆')) {
        text = 'chong qing ${text.split(' ').skip(2).join(' ')}';
      }
      if (name.startsWith('厦门')) {
        text = 'xia men ${text.split(' ').skip(2).join(' ')}';
      }
      return text.toLowerCase().trim();
    });

final _schoolRanks = <String, int>{};
final _educationSuffix =
    RegExp(r'\s*(?:[-—·]|[（(])?\s*(?:研究生(?:院|部)?|本科生?)\s*[）)]?$');
int _schoolRank(String name) => _schoolRanks.putIfAbsent(name, () {
      final normalized = name.replaceAll('(', '（').replaceAll(')', '）').trim();
      return _schoolRanking2026[normalized] ??
          _schoolRanking2026[normalized.replaceFirst(_educationSuffix, '')] ??
          1000000;
    });

int _compareSchools(JwxtSchoolProfile a, JwxtSchoolProfile b) {
  if (a.id == 'other') return b.id == 'other' ? 0 : 1;
  if (b.id == 'other') return -1;
  final rankOrder = _schoolRank(a.name).compareTo(_schoolRank(b.name));
  if (rankOrder != 0) return rankOrder;
  final order = _schoolSpelling(a.name).compareTo(_schoolSpelling(b.name));
  return order != 0 ? order : a.name.compareTo(b.name);
}

JwxtSchoolProfile _withResearchedEntry(JwxtSchoolProfile profile) {
  for (final entry in _schoolEntryDirectory) {
    if (entry.name == profile.name) {
      return JwxtSchoolProfile(
          id: profile.id,
          name: profile.name,
          aliases: profile.aliases,
          adapterId: profile.adapterId == 'generic'
              ? entry.adapterId
              : profile.adapterId,
          loginUrl: profile.loginUrl ?? entry.loginUrl,
          timetableUrl: profile.timetableUrl ?? entry.timetableUrl,
          sourceUrl: profile.sourceUrl ?? entry.sourceUrl,
          entryNote: profile.entryNote ?? entry.entryNote,
          educationLevel: entry.educationLevel,
          alternativeUrls: <String>{
            ...profile.alternativeUrls,
            ...entry.alternativeUrls,
          }.where((url) => url != profile.loginUrl).toList(growable: false),
          entryStatus:
              profile.loginUrl == null || profile.loginUrl == entry.loginUrl
                  ? entry.entryStatus
                  : null,
          authenticatedImportVerified: entry.authenticatedImportVerified,
          userReportedCapture:
              profile.userReportedCapture || entry.userReportedCapture);
    }
  }
  return profile;
}

List<JwxtSchoolProfile> searchJwxtSchools(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return jwxtSchoolDirectory;
  final compact = normalized.replaceAll(RegExp(r'\s+'), '');
  final matches = jwxtSchoolDirectory.where((profile) {
    if (profile.searchableText.contains(normalized)) return true;
    if (!RegExp(r'^[a-z]+$').hasMatch(compact)) return false;
    final spelling = _schoolSpelling(profile.name);
    final initials =
        spelling.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).join();
    return spelling.replaceAll(' ', '').contains(compact) ||
        initials.contains(compact);
  }).toList();
  matches.sort((a, b) {
    final aExact = a.name.toLowerCase() == normalized;
    final bExact = b.name.toLowerCase() == normalized;
    if (aExact == bExact) return _compareSchools(a, b);
    return aExact ? -1 : 1;
  });
  return List<JwxtSchoolProfile>.unmodifiable(matches);
}
