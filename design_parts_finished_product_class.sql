/*
    成品分类物料（Design 视图）

    查出分类全路径以「零件分类/产成品」开头的物料。
    每个物料编码一行（同一编码的多个版本已去掉）。

    结果列：
        part_number  物料编码（WTPartMaster.wtpartnumber）
        view_name    视图，只保留 Design
        part_cls     分类内部名，例如 GN_MECHANICALSOCKET
        full_path    分类全路径，例如 零件分类/产成品/移动式插座

    ---------------------------------------------------------------------------
    换环境时先执行下面三段，再改本文件里标了【替换】的三处。
    ida2a2 不能从别的库抄。测试库和正式库的分类节点 id、内部名都不一样。
    ---------------------------------------------------------------------------

    1) 找「零件分类」根，以及它的直接子节点。
       在结果里看 disp：
         根那一行的 disp = 零件分类，记下 ida2a2、name
         子节点里 disp = 产成品，记下 ida2a2、name、parent_id
       产成品的 ida2a2 替换主查询里的【替换1】。

        SELECT c.ida2a2,
               c.name,
               c.ida3a4 AS parent_id,
               c.deletedid,
               v.value  AS disp
        FROM LWCStructEnumAttTemplate r
        JOIN LWCStructEnumAttTemplate c
          ON c.ida2a2 = r.ida2a2
          OR c.ida3a4 = r.ida2a2
        JOIN LWCLocalizablePropertyValue v
          ON v.ida3b4 = c.ida2a2
        JOIN LWCPropertyDefinition lpd
          ON v.ida3a4 = lpd.ida2a2
         AND lpd.name = 'displayName'
        WHERE r.name = 'GN_PartFamily';

       若这一句没有行，根的内部名不是 GN_PartFamily。改跑：

        SELECT lt.ida2a2, lt.name, lt.ida3a4 AS parent_id, v.value AS disp
        FROM LWCStructEnumAttTemplate lt
        JOIN LWCLocalizablePropertyValue v
          ON v.ida3b4 = lt.ida2a2
        JOIN LWCPropertyDefinition lpd
          ON v.ida3a4 = lpd.ida2a2
         AND lpd.name = 'displayName'
        WHERE TO_CHAR(lt.ida3a4) = '0';

       用查到的根 name 换回上一句的 r.name，再取出「产成品」的 ida2a2。

    2) 确认物料上的分类属性名，以及对象类型。
       NAME 替换主查询里的【替换2】。
       CLASSNAMEKEYA4 替换主查询里的【替换3】。
       两库目前都是 part / wt.part.WTPart，不一样时才改。

        SELECT sd.name, sv.classnamekeya4, sv.value
        FROM StringValue sv
        JOIN StringDefinition sd
          ON sv.ida3a6 = sd.ida2a2
        WHERE sv.classnamekeya4 = 'wt.part.WTPart'
          AND UPPER(sv.value) LIKE 'GN_%'
          AND ROWNUM <= 10;

    3) 确认 Design 视图还叫这个名字。
       名称不是 Design 时，才改主查询里的【替换4】。
       正式库 Design 的 ida2a2 是 26729，SQL 按名称过滤，一般不用改 id。

        SELECT ida2a2, name
        FROM WTView
        WHERE name = 'Design';

    ---------------------------------------------------------------------------
    已经对过的环境（只作对照，换库以当场查询为准）

    测试库
        零件分类根     内部名 GN_PartFamily
        产成品         ida2a2 = 61498854，内部名 GN_FinishedProduct
        分类属性名     part
        对象类型       wt.part.WTPart
        视图           Design

    正式库 172.16.1.44 / WIND
        零件分类根     ida2a2 = 1057920795，内部名 GN_PartFamily，父节点 0
        产成品         ida2a2 = 1057961164，内部名 GN_FinishedPriduct，父节点 1057920795
        分类属性名     part
        对象类型       wt.part.WTPart
        视图           Design，ida2a2 = 26729

    主查询下面写的是正式库的产成品节点。
*/

WITH tree (ida2a2, name, full_path, lvl) AS (
    SELECT
        lt.ida2a2,
        lt.name,
        CAST(pv.value || '/' || v.value AS VARCHAR2(4000)),
        1
    FROM LWCStructEnumAttTemplate lt
    JOIN LWCStructEnumAttTemplate pt
      ON pt.ida2a2 = lt.ida3a4
    JOIN LWCLocalizablePropertyValue v
      ON v.ida3b4 = lt.ida2a2
    JOIN LWCPropertyDefinition lpd
      ON v.ida3a4 = lpd.ida2a2
     AND lpd.name = 'displayName'
    JOIN LWCLocalizablePropertyValue pv
      ON pv.ida3b4 = pt.ida2a2
    JOIN LWCPropertyDefinition ppd
      ON pv.ida3a4 = ppd.ida2a2
     AND ppd.name = 'displayName'
    WHERE lt.ida2a2 = 1057961164          /* 【替换1】产成品节点 ida2a2 */

    UNION ALL

    SELECT
        c.ida2a2,
        c.name,
        t.full_path || '/' || v.value,
        t.lvl + 1
    FROM LWCStructEnumAttTemplate c
    JOIN tree t
      ON c.ida3a4 = t.ida2a2
    JOIN LWCLocalizablePropertyValue v
      ON v.ida3b4 = c.ida2a2
    JOIN LWCPropertyDefinition lpd
      ON v.ida3a4 = lpd.ida2a2
     AND lpd.name = 'displayName'
    WHERE t.lvl < 20
)
SELECT DISTINCT
    m.wtpartnumber AS part_number,        /* 物料编码 */
    vw.name        AS view_name,          /* 视图 */
    sv.value       AS part_cls,           /* 分类内部名 */
    tree.full_path AS full_path           /* 分类全路径 */
FROM WTPart p
JOIN WTPartMaster m
  ON p.ida3masterreference = m.ida2a2
JOIN WTView vw
  ON vw.ida2a2 = p.ida3view
 AND vw.name = 'Design'                  /* 【替换4】视图名称，仅当不叫 Design 时修改 */
JOIN StringValue sv
  ON sv.ida3a4 = p.ida2a2
 AND sv.classnamekeya4 = 'wt.part.WTPart' /* 【替换3】StringValue.classnamekeya4 */
JOIN StringDefinition sd
  ON sv.ida3a6 = sd.ida2a2
 AND LOWER(sd.name) = 'part'              /* 【替换2】分类属性内部名 */
JOIN tree
  ON UPPER(tree.name) = UPPER(sv.value)
WHERE TO_CHAR(p.latestiterationinfo) = '1'
ORDER BY m.wtpartnumber;
